require 'rake'
require 'logger'
require 'excon'

module Rummager
    REPO_BASE = "clickbuild"
end

require 'rummager/containers'
require 'rummager/images'

# allow long runs through Excon, otherwise commands that
# take a long time will fail due to timeout
Excon.defaults[:write_timeout] = 1000
Excon.defaults[:read_timeout] = 1000

# provide Docker verboseness
if Rake.verbose == true
  Docker.logger = Logger.new(STDOUT)
  Docker.logger.level = Logger::DEBUG
end

task :"clean" => [ :"containers:clean", :"images:clean" ]

task :"clobber" => [ :"containers:clobber", :"images:clobber" ]


__END__
