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
## Batch processing commands
##
###########################################################

  class BatchJobTask < Rake::Task
    attr_accessor :create_args
    attr_accessor :start_args
    attr_accessor :idempotent
    attr_accessor :container_name
    attr_accessor :commit_changes

    def needed?
      if @idempotent == true
          true
        else
          print "WARN: #{@name}.needed? is not actually being checked"
          true
      end
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new do
        old_container = nil
        begin
          old_container = Docker::Container.get(@container_name)
        rescue
        end
          if old_container
            puts "'#{@name}' removing old batch container #{@container_name}"
            old_container.stop
            old_container.delete(:force => true)
          end
        
        puts "creating #{@create_args}"
        new_container = Docker::Container.create( @create_args )
        if fork
          puts "start"
          new_container.start( @start_args )
          Process.wait
        else
          puts "attach"
          new_container.attach({:stream => true,
                               :stdin => false,
                               :stdout => true,
                               :stderr => true,
                               :tty => true,
                               :logs => true}) { |chunk| puts chunk }
          Process.exit
          
        end
        if @commit_changes
          puts "'#{@name}' container #{@container_name} to be commited"
          new_container.commit
        else
          puts "'#{@name}' expiring container #{@container_name}"
          new_container.wait
          new_container.delete
        end
        puts "'#{@name}' complete"
      end
    end # initialize

  end # BatchJobTask

  class ClickJob < Rake::TaskLib
    attr_accessor :job_name
    attr_accessor :image_name
    attr_accessor :volumes_from
    attr_accessor :binds
    attr_accessor :dep_jobs
    attr_accessor :operation
    attr_accessor :idempotent
    attr_accessor :container_name
    attr_accessor :commit_changes

    def initialize(job_name,args={})
      @job_name = job_name
      @image_name = args.delete(:image_name)
      if !@image_name
        raise ArgumentError, "MUST define :image_name when creating ClickJob '#{@job_name}'"
      end
      @volumes_from = args.delete(:volumes_from)
      @binds = args.delete(:binds)
      @dep_jobs = args.delete(:dep_jobs)
      @operation = args.delete(:operation)
      if !@operation
        raise ArgumentError, "MUST define :operation when creating ClickJob '#{@job_name}'"
      end
      @idempotent = args.delete(:idempotent)
      @container_name = args.delete(:container_name) || "job_#{@job_name}"
      @commit_changes = args.delete(:commit_changes)
      if !args.empty?
        raise ArgumentError, "ClickJob'#{@job_name}' defenition has unused/invalid key-values:#{@args}"
      end
      yield self if block_given?
      define
    end #initialize

    def define
      namespace "batchjobs" do
        # do task
        gotask = Rummager::BatchJobTask.define_task :"#{@job_name}"
        gotask.create_args = CNTNR_ARGS_CREATE.clone
        gotask.create_args['Image'] = "#{Rummager.repo_base}/#{@image_name}:latest"
        gotask.create_args['name'] = @container_name
        gotask.create_args['Cmd'] = ["-c",@operation]
        
        gotask.start_args = {}
        if @volumes_from
          gotask.start_args['VolumesFrom'] = @volumes_from
        end
        if @binds
          gotask.start_args['Binds'] = @binds
        end
        gotask.idempotent = @idempotent
        gotask.container_name = @container_name
        gotask.commit_changes = @commit_changes
      end # namespace
      Rake::Task["batchjobs:#{@job_name}"].enhance( [ :"images:#{@image_name}:build" ] )
      if @volumes_from
        @volumes_from.each { |vf| Rake::Task["batchjobs:#{@job_name}"].enhance([:"containers:#{vf}:startonce" ]) }
      end
      if @dep_jobs
        @dep_jobs.each { |dj| Rake::Task["batchjobs:#{@job_name}"].enhance([ :"batchjobs:#{dj}" ]) }
      end
      if @commit_changes == true
        Rake::Task[:"containers:clobber"].enhance( [ :"containers:#{@container_name}:rm" ] )
      else
        Rake::Task[:"containers:clean"].enhance( [ :"containers:#{@container_name}:rm" ] )
      end
      
      namespace "containers" do
        namespace @container_name do
          # Remove task
          rmtask = Rummager::ContainerRMTask.define_task :rm
          rmtask.container_name = @container_name
        end # namespace @container_name
      end # namespace "containers"
      Rake::Task["images:#{@image_name}:rmi"].enhance( [ :"containers:#{@container_name}:rm" ] )
    end #define

  end # ClickJob


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
    
    def needed?
      if has_container?
        docker_obj.json['State']['Running'] == false
      else
        true
      end
    end
 
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        start_args = @args_start
        if @volumes_from
          puts "using VF:#{@volumes_from}"
          start_args.merge!( {'VolumesFrom' => @volumes_from} )
        end
        if @binds
          puts "using BINDS:#{@binds}"
          start_args['Binds'] = @binds
        end
        if @port_bindings
            puts "using PortBindings:#{@port_bindings}"
            start_args['PortBindings'] = @port_bindings
        end
        if @publishall
          start_args['PublishAllPorts'] = true
        end
        puts "Starting: #{@container_name}"
        docker_obj
          .start( start_args )
      }
    end # initialize
    
  end #ContainerStartTask


  class ContainerStartOnceTask < Rummager::ContainerTaskBase

    def needed?
      if has_container?
        if docker_obj.json['State']['Running'] == false
          puts "last:#{Time.parse(docker_obj.json['State']['StartedAt'])} !! #{Time.parse('0001-01-01T00:00:00Z')}"
          Time.parse(docker_obj.json['State']['StartedAt']) == Time.parse('0001-01-01T00:00:00Z')
        end
      else
        true
      end
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        Rake::Task["containers:#{@container_name}:start"].invoke
      }
    end # initialize

  end #ContainerStartOnceTask


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

  # base class for Container tasks
  class ContainerExec < Rummager::ContainerTaskBase
    attr_accessor :exec_name
    attr_accessor :container_name
    attr_accessor :command
    attr_accessor :stdin_pipe
    attr_accessor :show_output
    
    def has_container?
      ! container_obj.nil?
    end
    
    def container_obj
      begin
        @container_obj ||= Docker::Container.get(@container_name.to_s)
        rescue
        puts "WARNING: Docker::Container.get failed"
      end
    end
    
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "Starting: '#{@exec_name}' on container '#{@container_name}'"
        puts "Command is: '#{@command}'" if Rake.verbose == true
        exec_args = []
        exec_args.push( @command )
        exec_args.push( stdin: @stdin_pipe ) if !@stdin_pipe.nil
        if ( @show_output )
          container_obj.exec( exec_args ) { |stream, chunk| puts "#{chunk}" }
          else
          container_obj.exec( exec_args )
        end
      }
    end # initialize
    
  end # ContainerTaskBase


class ClickExec < Rake::TaskLib
  attr_accessor :exec_name
  attr_accessor :container_name
  attr_accessor :command
  attr_accessor :show_output
  attr_accessor :stdin_pipe
  attr_accessor :dep_execs
  
  def initialize(exec_name,args={})
    @exec_name = exec_name
    @container_name = args.delete(:container_name)
    if @container_name.nil?
      raise ArgumentError, "ClickExec '#{@exec_name}' required argument 'container_name' is undefined!"
    end
    @command = args.delete(:command)
    @dep_execs = args.delete(:dep_execs)
    @attach = args.delete(:attach)
    if !args.empty?
      raise ArgumentError, "ClickExec'#{@exec_name}' defenition has unused/invalid key-values:#{args}"
    end
    yield self if block_given?
    define
  end
  
  def define
    namespace "containers" do
      namespace @container_name do
        namespace "exec" do
          namespace @exec_name do
            # create exec task
            createexec = Rummager::ContainerExec.define_task :create
            createexec.container_name = @container_name
            createexec.command = @command
            createexec.show_output = @show_output
            createexec.stdin_pipe = @stdin_pipe
          end # @exec_name
        end # namespace "exec"
      end # namespace "continers"
    end # namespace "containers"
  end # define
end # class ClickExec

  class ContainerEnterTask < Rummager::ContainerTaskBase
    attr_accessor :env_name
    def needed?
      true
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "Entering: #{@env_name}"
        #        container_obj.start( @args_start )
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
    attr_accessor :enter_execs
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
      @enter_dep_jobs = args.delete(:enter_dep_jobs) || []
      @allow_enter = args.delete(:allow_enter)
      @noclean = args.delete(:noclean)
      if !args.empty?
        raise ArgumentError, "ClickJob'#{@job_name}' defenition has unused/invalid key-values:#{args}"
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
          oncetask = Rummager::ContainerStartOnceTask.define_task :startonce
          oncetask.container_name = @container_name
          
          starttask = Rummager::ContainerStartTask.define_task :start
          starttask.container_name = @container_name
          starttask.args_start = @args_start
          starttask.volumes_from = @volumes_from
          starttask.binds = @binds
          starttask.port_bindings = @port_bindings
          starttask.publishall = @publishall
          Rake::Task["containers:#{@container_name}:start"].enhance( [ :"containers:#{@container_name}:create" ] )
          if @volumes_from
            @volumes_from.each do |vf|
              Rake::Task["containers:#{@container_name}:create"].enhance([:"containers:#{vf}:startonce" ])
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
          Rake::Task["containers:#{@container_name}:create"].enhance( [ :"containers:#{@container_name}:rm" ] )
          
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
