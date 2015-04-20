rummager
========

Rake integration with docker-api for controling docker containers with build
tools like Yocto

Usage in Rakefile
-----------------

	require 'rummager'
  
	Rummager::ClickImage.new 'base_image'
  
	Rummager::ClickImage.new 'my_image', {
	  :dep_image => 'base_image',
	}
	# persistent container
	Rummager::ClickContainer.new 'build_container', {
	  :image_name => 'my_image',
	}
  
Install
=======

Building the GEM
----------------

	gem build ./rummager.gemspec
  
Installing the GEM
------------------

To install the GEM in your local repository

	gem install --user-isntall ./rummager-x.x.x.gem
  
To install the GEM as a global/system library

	sudo gem install ./rummager-x.x.x.gem
