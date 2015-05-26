rummager
========

Ruby Rake integration with Docker containers to encapsulate complete build
toolchains like Yocto

Usage
-------

### Bundler

It is strongly recommended to use Bundler:

```ruby
require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
```

## Gemfile
The Gemfile should contain the following:

    source 'https://rubygems.org'
    gem 'rake', 	'>=10.4.2'
    gem 'excon', '~>0.45.3'

    gem 'rummager', :git => 'https://github.com/exactassembly/rummager.git'


If Bundler is used as above, then execution of Rake should be through the
"bundler exec" syntax:

```shell
$ bundler exec rake <target name>
```

Validation
----------------
To validate the library, it must be run inside the Rake framework, to assist
with this the validation/ subdirectory is a Rakelib directory containing
an set of .rake files with pre-defined docker images, containers, exec tasks
and a top level set of tests to be run. This can be run with the following
command:

```shell
rake -I lib/ -R validation/ test_all
```

Building the GEM
----------------

	gem build ./rummager.gemspec
  
