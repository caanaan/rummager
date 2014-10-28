Gem::Specification.new do |s|
  s.name = 'rummager'
  s.version = '0.2.2'
  s.date = '2014-10-28'
  s.summary = 'Rummager'
  s.description = 'Rake automation of Cross-Compiler toolchains, particularlty Yocto'
  s.authors = ["Ted Vaida, KS Technologies LLC"]
  s.email = 'ted@kstechnologies.com'
  s.homepage = 'https://rubygems.org/gems/rummager'
  s.license = 'Proprietary'
  s.files = ['lib/rummager.rb',
                'lib/rummager/containers.rb',
                'lib/rummager/images.rb',
                'lib/rummager/util.rb',
                ]
  s.add_runtime_dependency "rake", [">= 10.3.2"]
  s.add_runtime_dependency "logger", [">= 1.2.8"]
  s.add_runtime_dependency "docker-api", [">= 1.13.2"]
  s.add_runtime_dependency "json", [">= 1.7.7"]
end
