require 'rummager'
require 'docker'

describe Rummager::ClickImage, "#images" do
  before(:all) do
    begin
      Dir.rmdir("foo")
    rescue
    end
  end

it "returns !nil" do
    Dir.mkdir("foo")
    new_image = Rummager::ClickImage.new( "dirimg", source: Dir.new("foo") )
    expect( new_image ).to_not be_nil
    
    image_from = "busybox"
    source_string = %Q{
        FROM #{image_from}
        CMD ['echo "READY" && exit']
    }
    Rummager.repo_base = "spectest"
    new_string_image_task = Rummager::ClickImage.new( "stringimage", source: source_string )
    expect( new_string_image_task ).to_not be_nil
    new_string_image_task.execute(0)
    docker_stringimage = Docker::Image.search( "Repo" => "spectest/stringimage")
    expect ( docker_stringimage ).to_not be_nil
    docker_stringimage.remove(:force => true)
  end
  
  after(:all) do
    begin
    rescue
    end
    begin
      Dir.rmdir("foo")
    rescue
    end
  end
end