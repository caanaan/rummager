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
    attr_accessor :exec_once
    attr_accessor :exec_always
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
          start_args['PublishAllPorts'] = true  if Rake.verbose == true
        end
        puts "Starting: #{@container_name}"
        docker_obj
          .start( start_args )
        if @exec_list
          puts "exec_list"
          begin
            exec_list.each do |ae|
              if ae.delete(:show_output)
                puts "showing exec output"
                docker_obj.exec(ae.delete(:cmd),ae) { |stream,chunk| puts chunk }
              else
                puts "silent exec"
                docker_obj.exec(ae.delete(:cmd),ae)
              end
            end
          rescue => ex
            raise IOError, "exec failed:#{ex.message}"
          end
        end
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
    attr_accessor :exec_once
    attr_accessor :exec_always
    attr_accessor :start_once
    attr_accessor :allow_enter
    attr_accessor :noclean
  
    def initialize(container_name,args={})
      @container_name = container_name
      @image_name = args.delete(:image_name) || container_name
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
      @exec_once = args.delete(:exec_once)
      @exec_always = args.delete(:exec_always)
      @start_once = args.delete(:start_once)
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
          createtask = Rummager::ContainerCreateTask.define_task :create
          createtask.container_name = @container_name
          createtask.image_name = @image_name
          createtask.repo_base = @repo_base
          createtask.args_create = @args_create
          createtask.command = @command
          createtask.exposed_ports = @exposed_ports
          Rake::Task["containers:#{@container_name}:create"].enhance( [ :"images:#{@image_name}:build" ] )
          if @dep_jobs
            @dep_jobs.each do |dj|
              Rake::Task["containers:#{@container_name}:create"].enhance( [ :"batchjobs:#{dj}" ] )
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
          starttask.exec_once = @exec_once
          starttask.exec_always = @exec_always
          starttask.start_once = @start_once
          
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
              Rake::Task["containers:#{@container_name}:enter"].enhance([ :"batchjobs:#{edj}" ])
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
          Rake::Task["images:#{@image_name}:rmi"].enhance( [ "containers:#{@container_name}:rm" ] )
          Rake::Task["containers:#{@container_name}:rm"].enhance( [ :"containers:#{@container_name}:stop" ] )
          
          if @noclean == true
            Rake::Task[:"containers:clobber"].enhance( [ :"containers:#{@container_name}:rm" ] )
          else
            Rake::Task[:"containers:clean"].enhance( [ :"containers:#{@container_name}:rm" ] )
          end
          
        end # namespace
      end # namespace
        
      Rake::Task["containers:#{@container_name}:rm"].enhance( [ :"containers:#{@container_name}:stop" ] )
      Rake::Task[:"containers:stop"].enhance( [ :"containers:#{@container_name}:stop" ] )

    end # define
  end # ClickContainer
  
end   # module Rummager

__END__
