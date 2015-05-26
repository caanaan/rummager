require 'rake'
require 'logger'
require 'rummager'

Rummager.repo_base = "rummagertest"

Rummager::ClickImage.new 'img_one', {
    :source => %Q{
        FROM busybox
        VOLUME /volumetest
        CMD ["/bin/false"]
    },
    :noclean => true,
}

Rummager::ClickImage.new 'img_two', {
    :source => %Q{
        FROM #{Rummager.repo_base}/img_one
        ENTRYPOINT ["/bin/sh","--login"]
    },
    :add_files => [
      'README.md',
    ]
}

task :test_image_build => [
    :"images:img_one:build",
    :"images:img_two:build",
]

task :test_image_rmi => [
    :"images:img_two:rmi",
    :"images:img_one:rmi",
]
