require 'rake'
require 'logger'
require 'rake/tasklib'
require 'docker'
require 'date'
require 'digest'
require 'json'
require 'excon'
require 'time'

# Create and describe generic container operation targets
namespace :containers do
    
    desc "Start background containers"
    task :"start"
    
    desc "Stop background containers"
    task :"stop"
    
    desc "Remove temporary containers"
    task :"clean"
    
    desc "Remove all Docker containters including caches"
    task :"clobber" => [ :"containers:clean" ]
    
end
    
module Rummager
    
  CNTNR_ARGS_CREATE = {
    'AttachStdin' => true,
    'AttachStdout' => true,
    'AttachStderr' => true,
    'OpenStdin' => true,
    'Tty' => true,
  }

###########################################################
##
## Container Handling Pieces
##
###########################################################

  # Abstract base class for Container tasks
  class ContainerTaskBase < Rake::Task
    attr_accessor :container_name

    def docker_obj
      begin
        @container_obj ||= Docker::Container.get(@container_name.to_s)
      rescue
      end
    end

    def has_container?
      ! docker_obj.nil?
    end

    def is_running?
      container_obj.json['State']['Running'] == false
    end

    def never_ran?
      if has_container?
        if docker_obj.json['State']['Running'] == true
          puts "#{@container_name} is running!"  if Rake.verbose == true
          false
        else
        end
      else
        true
      end
    end

    def exit_code
      container_obj.json['State']['ExitCode']
    end
    
  end # ContainerTaskBase

  class ContainerCreateTask < Rummager::ContainerTaskBase
    attr_accessor :args_create
    attr_accessor :command
    attr_accessor :exposed_ports
    attr_accessor :image_name
    attr_accessor :repo_base
    
    def needed?
      ! has_container?
    end
    
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        create_args = @args_create
        create_args['Image'] = "#{@repo_base}/#{@image_name}:latest"
        create_args['name'] = @container_name
        if @command
          create_args['Cmd'] = @command
        end
        if @exposed_ports
          create_args['ExposedPorts'] = {};
          @exposed_ports.each do |prt|
            create_args['ExposedPorts'][prt] = {}
          end
        end
        newcont = Docker::Container.create( create_args )
        puts "created container '#{@container_name}' -> #{newcont.json}" if Rake.verbose == true
      }
    end

  end #ContainerCreateTask


  class ContainerStartTask < Rummager::ContainerTaskBase
    attr_accessor :volumes_from
    attr_accessor :args_start
    attr_accessor :binds
    attr_accessor :port_bindings
    attr_accessor :publishall
    attr_accessor :exec_on_start
    attr_accessor :start_once
    
    def needed?
      if has_container?
        puts "checking if #{@container_name} is running" if Rake.verbose == true
        if docker_obj.json['State']['Running'] == false
          puts "#{@container_name} is NOT running"  if Rake.verbose == true
          if Time.parse(docker_obj.json['State']['StartedAt']) != Time.parse('0001-01-01T00:00:00Z')
            puts "#{@container_name} previously ran"  if Rake.verbose == true
            if @start_once == true
              puts "#{@container_name} is a start_once container, not needed" if Rake.verbose == true
              return false
            end
          else
            puts "#{@container_name} has never run" if Rake.verbose == true
          end
        else
          puts "#{@container_name} is running" if Rake.verbose == true
        end
      else
        puts "#{@container_name} doesnt exist" if Rake.verbose == true
      end
      true
    end
 
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        start_args = @args_start
        if @volumes_from
          puts "using VF:#{@volumes_from}"  if Rake.verbose == true
          start_args.merge!( {'VolumesFrom' => @volumes_from} )
        end
        if @binds
          puts "using BINDS:#{@binds}"  if Rake.verbose == true
          start_args['Binds'] = @binds
        end
        if @port_bindings
            puts "using PortBindings:#{@port_bindings}"  if Rake.verbose == true
            start_args['PortBindings'] = @port_bindings
        end
        if @publishall
          start_args['PublishAllPorts'] = true
        end
        puts "Starting: #{@container_name}"
        docker_obj.start( start_args )
        if @exec_on_start
          begin
            puts "issuing exec calls" if Rake.verbose == true
            exec_on_start.each do |ae|
              if ae.delete(:hide_output)
                docker_obj.exec(ae.delete(:cmd),ae)
              else
                docker_obj.exec(ae.delete(:cmd),ae) { |stream,chunk| puts "#{chunk}" }
              end
              puts "all exec calls complete" if Rake.verbose == true
            end
          rescue => ex
            raise IOError, "exec failed:#{ex.message}"
          end
        end # @exec_on_start
      }
    end # initialize
    
  end #ContainerStartTask

  class ContainerStopTask < Rummager::ContainerTaskBase

    def needed?
      if has_container?
          docker_obj.json['State']['Running'] == true
        else
          false
      end
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "Stopping #{@container_name}" if Rake.verbose == true
        docker_obj.stop
      }
    end
    
  end #ContainerStopTask


  class ContainerRMTask < Rummager::ContainerTaskBase
  
    def needed?
      puts "checking needed? for rm:#{@container_name}" if Rake.verbose == true
      has_container?
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "removing container #{@name}:#{docker_obj.to_s}" if Rake.verbose == true
        docker_obj.delete(:force => true, :v => true)
      }
    end #initialize

  end #ContainerRMTask

  class ContainerEnterTask < Rummager::ContainerTaskBase
    attr_accessor :env_name
    def needed?
      true
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "Entering: #{@container_name}"
        exec "docker attach #{docker_obj.id}"
      }
    end # initialize

  end #ContainerEnterTask


  # Template to generate tasks for Container lifecycle
  class ClickContainer < Rake::TaskLib
    attr_accessor :container_name
    attr_accessor :image_name
    attr_accessor :image_nobuild
    attr_accessor :repo_base
    attr_accessor :command
    attr_accessor :args_create
    attr_accessor :args_start
    attr_accessor :volumes_from
    attr_accessor :binds
    attr_accessor :exposed_ports
    attr_accessor :port_bindings
    attr_accessor :publishall
    attr_accessor :dep_jobs
    attr_accessor :exec_on_start
    attr_accessor :allow_enter
    attr_accessor :enter_dep_jobs
    attr_accessor :noclean
  
    def initialize(container_name,args={})
      @container_name = container_name
      @image_name = args.delete(:image_name) || container_name
      @image_nobuild = args.delete(:image_nobuild)
      @repo_base = args.delete(:repo_base) || Rummager.repo_base
      @command = args.delete(:command)
      @args_create = args.delete(:args_create) || CNTNR_ARGS_CREATE
      @args_start = args.delete(:args_start) || {}
      @volumes_from = args.delete(:volumes_from)
      @binds = args.delete(:binds)
      @exposed_ports = args.delete(:exposed_ports)
      @port_bindings = args.delete(:port_bindings)
      if (!@exposed_ports.nil? && !@port_bindings.nil?)
        puts "WARNING: both 'exposed_ports' and 'port_bindings' are defined on #{@container_name}"
      end
      @publishall = args.delete(:publishall)
      @dep_jobs = args.delete(:dep_jobs)
      @exec_on_start = args.delete(:exec_on_start)
      @enter_dep_jobs = args.delete(:enter_dep_jobs) || []
      @allow_enter = args.delete(:allow_enter)
      @noclean = args.delete(:noclean)
      if !args.empty?
        raise ArgumentError, "ClickContainer'#{@container_name}' defenition has unused/invalid key-values:#{args}"
      end
      yield self if block_given?
      define
    end
      
    def define
      namespace "containers" do
        namespace @container_name do
          # create task
          realcreatetask = Rummager::ContainerCreateTask.define_task :create
          realcreatetask.container_name = @container_name
          realcreatetask.image_name = @image_name
          realcreatetask.repo_base = @repo_base
          realcreatetask.args_create = @args_create
          realcreatetask.command = @command
          realcreatetask.exposed_ports = @exposed_ports
          
          if @image_nobuild == true
            puts "skipping image build - assuming it exists" if Rake.verbose == true
          else
            Rake::Task["containers:#{@container_name}:create"].enhance( [ :"images:#{@image_name}:build" ] )
          end
          
          if @dep_jobs
            @dep_jobs.each do |dj|
              Rake::Task["containers:#{@container_name}:create"].enhance( [ :"#{dj}" ] )
            end
          end

          # start task
          starttask = Rummager::ContainerStartTask.define_task :start
          starttask.container_name = @container_name
          starttask.args_start = @args_start
          starttask.volumes_from = @volumes_from
          starttask.binds = @binds
          starttask.port_bindings = @port_bindings
          starttask.publishall = @publishall
          starttask.exec_on_start = @exec_on_start
          
          Rake::Task["containers:#{@container_name}:start"].enhance( [ :"containers:#{@container_name}:create" ] )
          if @volumes_from
            @volumes_from.each do |vf|
              Rake::Task["containers:#{@container_name}:create"].enhance([:"containers:#{vf}:start" ])
            end
          end
          if @allow_enter
            # build and jump into an environment
            entertask = Rummager::ContainerEnterTask.define_task :enter
            entertask.container_name = @container_name
            @enter_dep_jobs.each do |edj|
              Rake::Task["containers:#{@container_name}:enter"].enhance([ :"containers:#{@container_name}:jobs:#{edj}" ])
            end
            Rake::Task["containers:#{@container_name}:enter"].enhance([ :"containers:#{@container_name}:start" ])
          end # allow_enter

          # stop task
          stoptask = Rummager::ContainerStopTask.define_task :stop
          stoptask.container_name = @container_name
          Rake::Task[:"containers:stop"].enhance( [ :"containers:#{@container_name}:stop" ] )
          
          # Remove task
          rmtask = Rummager::ContainerRMTask.define_task :rm
          rmtask.container_name = @container_name
          if @image_nobuild == true
            puts "skipping #{@image_name}:rmi dependency on #{@container_name}:rm" if Rake.verbose == true
          else
            Rake::Task["images:#{@image_name}:rmi"].enhance( [ "containers:#{@container_name}:rm" ] )
          end
          
          Rake::Task["containers:#{@container_name}:rm"].enhance( [ :"containers:#{@container_name}:stop" ] )
          
          if @noclean == true
            Rake::Task[:"containers:clobber"].enhance( [ :"containers:#{@container_name}:rm" ] )
          else
            Rake::Task[:"containers:clean"].enhance( [ :"containers:#{@container_name}:rm" ] )
          end
          
        end # namespace @container_name
      end # namespace "containers"
        
      Rake::Task["containers:#{@container_name}:rm"].enhance( [ :"containers:#{@container_name}:stop" ] )
      Rake::Task[:"containers:stop"].enhance( [ :"containers:#{@container_name}:stop" ] )

    end # define
  end # class ClickContainer


  class ContainerExecTask < Rummager::ContainerTaskBase
    attr_accessor :exec_list
    attr_accessor :ident_hash

    def ident_filename
      "/.once-#{@ident_hash}"
    end

    def needed?
      if ! @ident_hash.nil?
        puts "checking for #{ident_filename} in container" if Rake.verbose == true
        begin
          docker_obj.copy("#{ident_filename}")
          return false
        rescue
          puts "#{ident_filename} not found" if Rake.verbose == true
        end
      end
      # no ident hash, or not found
      true
    end
    
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
  
        @exec_list.each do |e|
          
          hide_output = e.delete(:hide_output)
          cmd = e.delete(:cmd)
          restart_after = e.delete(:restart_after)
          
          if hide_output == true
            docker_obj.exec(cmd)
          else
          docker_obj.exec(cmd) { |stream,chunk| puts "#{chunk}" }
          end
        
          if restart_after==true
            puts "exec item requires container restart" if Rake.verbose == true
            docker_obj.restart()
          end
          
        end # @exec_list.each

        if ! @ident_hash.nil?
          puts "marking #{task_name} completed: #{ident_filename}" if Rake.verbose == true
          docker_obj.exec(["/usr/bin/sudo","/usr/bin/touch","#{ident_filename}"])
        end

      }
      
    end # initialize
    
  end # class ContainerExecTask


  class ClickCntnrExec < Rake::TaskLib
    attr_accessor :job_name
    attr_accessor :container_name
    attr_accessor :exec_list
    attr_accessor :ident_hash
    attr_accessor :dep_jobs
    
    def initialize(job_name,args={})
      @job_name = job_name
      if !args.delete(:run_always)
        @ident_hash = Digest::MD5.hexdigest(args.to_s)
        puts "#{job_name} ident: #{@ident_hash}" if Rake.verbose == true
      end
      
      @container_name = args.delete(:container_name)
      if !defined? @container_name
        raise ArgumentError, "ClickContainer'#{@job_name}' missing comtainer_name:#{args}"
      end
      @exec_list = args.delete(:exec_list)
      @dep_jobs = args.delete(:dep_jobs)
      if !args.empty?
        raise ArgumentError, "ClickExec'#{@job_name}' defenition has unused/invalid key-values:#{args}"
      end
      yield self if block_given?
      define
    end  # initialize
    
    
    def define
      
      namespace "containers" do
        namespace @container_name do
          namespace "jobs" do
            
            exectask = Rummager::ContainerExecTask.define_task :"#{job_name}"
            exectask.container_name = @container_name
            exectask.exec_list = @exec_list
            exectask.ident_hash = @ident_hash
            Rake::Task[:"containers:#{@container_name}:jobs:#{job_name}"].enhance( [:"containers:#{@container_name}:start"] )
            if @dep_jobs
                @dep_jobs.each do |dj|
                    Rake::Task["containers:#{@container_name}:jobs:#{job_name}"].enhance([ :"containers:#{@container_name}:jobs:#{dj}" ])
                end
            end
            
          end # namespave "jobs"
        end # namespace @container_name
      end # namespace "containers"
      
    end # define
    
  end # class ClickCntnrExec


end   # module Rummager

__END__
