# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rummager/version'

Gem::Specification.new do |spec|
    spec.name = "rummager"
    spec.version = Rummager::VERSION
    spec.authors = ["y3ddet"]
    spec.email = ["ted@xassembly.com"]
    spec.summary = %q{Rummager - Docker integration with Rake}
    spec.description = %q{Rummager provides glue to manage Docker images and containers from Rake}
    spec.homepage = "https://github.com/exactassembly/rummager"
    spec.license = "GPLv2"

    spec.files = [
        'lib/rummager.rb',
        'lib/rummager/containers.rb',
        'lib/rummager/images.rb',
        'lib/rummager/util.rb',
    ]
    spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
    spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
    spec.require_paths = ["lib"]

    spec.add_development_dependency "bundler", "~> 1.7"
    spec.add_development_dependency "rake", "~> 10.0"

    spec.add_runtime_dependency "rake", ">= 10.3.2"
    spec.add_runtime_dependency "logger", ">= 1.2.8"
    spec.add_runtime_dependency "json", ">= 1.7.7"
    spec.add_runtime_dependency "docker-api", ">= 1.21.4"
end
