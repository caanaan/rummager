require 'rake'
require 'logger'
require 'rake/tasklib'
require 'docker'
require 'date'
require 'digest'
require 'json'
require 'excon'
require 'time'
require 'rummager/util'

# Create and describe generic image operation targets
namespace :images do
  desc "Build all Docker images"
  task :"build"
  
  desc "Remove temporary images"
  task :"clean" => [ :"containers:clean" ]
  
  desc "Remove all Docker images"
  task :"clobber" => [ :"containers:clobber", :"images:clean" ]
end

###########################################################
##
## Image Handling Pieces
##
###########################################################

# Abstract base class for Image handling tasks
class Rummager::ImageTaskBase < Rake::Task
    attr_accessor :repo
    attr_accessor :tag

    def has_repo?
      Docker::Image.all(:all => true).any? { |image| image.info['RepoTags'].any? { |s| s.include?(@repo) } }
    end
    
end # ImageTaskBase

# Image build tasks
class Rummager::ImageBuildTask < Rummager::ImageTaskBase
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
  class Rummager::ImageRMITask < Rummager::ImageTaskBase

    def needed?
      has_repo?
    end

    def initialize(task_name, app)
      super(task_name,app)
      @actions << Proc.new {
        puts "removing image '#{t.repo}'" if Rake.verbose == true
        Docker::Image.all(:all => true).each do |img|
          if img.info['RepoTags'].any? { |s| s.include?(@repo) }
            begin
              img.delete(:force => true)
            rescue Exception => e
              puts "exception: #{e.message}" if Rake.verbose == true
            end
          end
        end #each
      }
    end # initialize

  end #DockerImageRMITask


  # Template to generate tasks for Docker Images
  class Rummager::ClickImage < Rake::TaskLib

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
      @image_args[:repo] = "#{Rummager::REPO_BASE}/#{image_name}"
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


__END__