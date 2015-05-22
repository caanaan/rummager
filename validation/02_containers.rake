require 'rake'
require 'logger'
require 'rummager'

Rummager::ClickContainer.new 'container_one', {
    :image_name => 'img_one',
    :noclean => 'false',
}

Rummager::ClickContainer.new 'container_two', {
    :image_name => 'img_two',
    :volumes_from => ['container_one'],
}

task :test_container_start => [
    :"containers:container_one:start",
    :"containers:container_two:start",
]

task :test_container_stop => [
    :"containers:container_two:stop",
    :"containers:container_one:stop",
]

task :test_container_rm => [
    :"containers:container_two:rm",
    :"containers:container_one:rm",
]
