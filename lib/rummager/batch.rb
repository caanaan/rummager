require 'rake'
require 'logger'
require 'rake/tasklib'
require 'docker'
require 'date'
require 'digest'
require 'json'
require 'excon'
require 'time'


###########################################################
##
## Batch processing commands
##
###########################################################

class Rummager::BatchJobTask < Rake::Task
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

class Rummager::ClickJob < Rake::TaskLib
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
  

__END__
