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
