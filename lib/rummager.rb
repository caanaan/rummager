require 'rake'
require 'logger'
require 'rake/tasklib'
require 'docker'
require 'date'
require 'digest'
require 'json'
require 'excon'
require 'time'

Excon.defaults[:write_timeout] = 1000
Excon.defaults[:read_timeout] = 1000

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

# Create and describe generic image operation targets
namespace :images do
  desc "Build all Docker images"
  task :"build"
  
  desc "Remove temporary images"
  task :"clean" => [ :"containers:clean" ]
  
  desc "Remove all Docker images"
  task :"clobber" => [ :"containers:clobber", :"images:clean" ]
end

task :"clean" => [ :"containers:clean", :"images:clean" ]

task :"clobber" => [ :"containers:clobber", :"images:clobber" ]

module Rummager
  
  def Rummager.fingerprint ( name )
    image_dir = File.join( Rake.application.original_dir, name )
    raise IOError, "Directory '#{image_dir}' does not exist!" if ! File::exist?( image_dir )
    files = Dir["#{image_dir}/**/*"].reject{ |f| File.directory?(f) }
    content = files.map{|f| File.read(f)}.join
    Digest::MD5.hexdigest(content)
  end

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
        gotask.create_args['Image'] = "#{REPO_BASE}/#{@image_name}:latest"
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
    attr_accessor :image_name
    
    def image_repo
      "#{REPO_BASE}/#{@image_name}:latest"
    end
    
    def has_container?
      ! container_obj.nil?
    end

    def container_obj
      begin
        @container_obj ||= Docker::Container.get(@container_name.to_s)
      rescue
      end
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
  
    def needed?
      ! has_container?
    end
    
    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        create_args = @args_create
        create_args['Image'] = image_repo
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
        container_obj.json['State']['Running'] == false
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
        container_obj
          .start( start_args )
      }
    end # initialize
    
  end #ContainerStartTask


  class ContainerStartOnceTask < Rummager::ContainerTaskBase

    def needed?
      if has_container?
        if container_obj.json['State']['Running'] == false
          puts "last:#{Time.parse(container_obj.json['State']['StartedAt'])} !! #{Time.parse('0001-01-01T00:00:00Z')}"
          Time.parse(container_obj.json['State']['StartedAt']) == Time.parse('0001-01-01T00:00:00Z')
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
          container_obj.json['State']['Running'] == true
        else
          false
      end
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "Stopping #{@container_name}" if Rake.verbose == true
        container_obj.stop
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
        puts "removing container #{@name}:#{t.container_obj.to_s}" if Rake.verbose == true
        container_obj.delete(:force => true)
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
        puts "Entering: #{@env_name}"
        container_obj.start( @args_start )
        exec "docker attach #{container_obj.id}"
      }
    end # initialize

  end #ContainerEnterTask


  # Template to generate tasks for Container lifecycle
  class ClickContainer < Rake::TaskLib
    attr_accessor :container_name
    attr_accessor :image_name
    attr_accessor :command
    attr_accessor :args_create
    attr_accessor :args_start
    attr_accessor :volumes_from
    attr_accessor :binds
    attr_accessor :exposed_ports
    attr_accessor :port_bindings
    attr_accessor :publishall
    attr_accessor :dep_jobs
    attr_accessor :enter_dep_jobs
    attr_accessor :allow_enter
    attr_accessor :noclean
  
    def initialize(container_name,args={})
      @container_name = container_name
      @image_name = args.delete(:image_name) || container_name
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
  


###########################################################
##
## Image Handling Pieces
##
###########################################################

  # Abstract base class for Image handling tasks
  class ImageTaskBase < Rake::Task
    attr_accessor :repo
    attr_accessor :tag

    def has_repo?
      Docker::Image.all(:all => true).any? { |image| image.info['RepoTags'].any? { |s| s.include?(@repo) } }
    end
    
  end # ImageTaskBase

  # Image build tasks
  class ImageBuildTask < Rummager::ImageTaskBase
    attr_accessor :sourcedir
    attr_accessor :fingerprint

    IMG_BUILD_ARGS = {
      :forcerm => true,
      :rm => true,
    }

    def fingerprint
      @fingerprint ||= Rummager.fingerprint(@sourcedir)
    end

    def needed?
      !Docker::Image.all(:all => true).any? { |image| image.info['RepoTags'].any? { |s| s.include?("#{@repo}:#{fingerprint}") } }
    end
    
    def initialize(task_name, app)
      super(task_name,app)
      @build_args = IMG_BUILD_ARGS
      @actions << Proc.new {
        @build_args[:'t'] = "#{@repo}:#{fingerprint}"
        puts "Image '#{@repo}': begin build"
        newimage = Docker::Image.build_from_dir( @sourcedir, @build_args ) do |c|
          begin
            print JSON(c)['stream']
          rescue
            print "WARN JSON parse error with:" + c
          end
        end
        newimage.tag( 'repo' => @repo,
                      'tag' => 'latest' )
        puts "Image '#{@repo}': build complete"
        puts "#{@build_args} -> #{newimage.json}" if Rake.verbose == true
      }
    end #initialize
    
  end #ImageBuildTask


  # Image removal tasks
  class ImageRMITask < Rummager::ImageTaskBase

    def needed?
      has_repo?
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "removing image '#{t.repo}'" if Rake.verbose == true
        Docker::Image.all(:all => true).each do |img|
          if img.info['RepoTags'].any? { |s| s.include?(@repo) }
            img.delete(:force => true)
          end
        end #each
      }
    end # initialize

  end #DockerImageRMITask


  # Template to generate tasks for Docker Images
  class ClickImage < Rake::TaskLib

    attr_accessor :image_name
    attr_accessor :image_args
    attr_accessor :sourcedir
    attr_accessor :dep_image
    attr_accessor :dep_other
    attr_accessor :noclean
    
    def initialize(image_name,args={})
      @image_name = image_name
      @dep_image = args.delete(:dep_image)
      @dep_other = args.delete(:dep_other)
      @noclean = args.delete(:noclean)
      @sourcedir = args.delete(:sourcedir) || "#{image_name}"
      @image_args = args
      @image_args[:repo] = "#{REPO_BASE}/#{image_name}"
      @image_args[:tag] ||= 'latest'
      yield self if block_given?
      define
    end
    
    def define
      namespace "images" do
        namespace @image_name do
          
          rmitask = Rummager::ImageRMITask.define_task :rmi
          rmitask.repo = "#{@image_args[:repo]}"
          rmitask.tag = 'latest'
          
          buildtask = Rummager::ImageBuildTask.define_task :build
          buildtask.repo = @image_args[:repo]
          buildtask.tag = Rummager::fingerprint( @sourcedir )
          buildtask.sourcedir = @sourcedir
          
        end # namespace
      end # namespace

      if @dep_image
        # forward prereq for build
        Rake::Task[:"images:#{@image_name}:build"].enhance( [ :"images:#{@dep_image}:build" ] )
        # reverse prereq on parent image for delete
        Rake::Task[:"images:#{@dep_image}:rmi"].enhance(["images:#{@image_name}:rmi"])
      end
      if @dep_other
        Rake.Task[:"images:#{@image_name}"].enhance( @dep_other )
      end

      if @noclean
        Rake::Task[:"images:clobber"].enhance( [ :"images:#{@image_name}:rmi"] )
      else
        Rake::Task[:"images:clean"].enhance( [ :"images:#{@image_name}:rmi"] )
      end

    end # ClickImage.define

  end # class ClickImage

end   # module Rummager

__END__
