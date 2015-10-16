Gem::Specification.new do |s|
  s.name = 'rummager'
  s.version = '0.5.13'
  s.date = '2015-10-16'
  s.summary = 'Rummager'
  s.description = 'Rake integration with docker-api'
  s.authors = ["y3ddet, ted@xassembly.com"]
  s.email = 'ted@xassembly.com'
  s.homepage = 'https://github.com/exactassembly/rummager'
  s.license = 'GPLv2'
  s.files = ['lib/rummager.rb',
                'lib/rummager/containers.rb',
                'lib/rummager/images.rb',
                'lib/rummager/util.rb',
                ]
  s.add_runtime_dependency "rake", [">= 10.3.2"]
  s.add_runtime_dependency "logger", [">= 1.2.8"]
  s.add_runtime_dependency "json", [">= 1.7.7"]
  s.add_runtime_dependency "docker-api", [">= 1.21.4"]
end
