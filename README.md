ahn_cloud
=========

Cloud-Based Platform for Adhearsion apps

Installation
------------
To install ahncloud simply pull down the repository locally and execute bundle install

Start AHN Cloud:
ruby sinatra.rb

Start Jabber Queue
ruby jabber_queue.rb

Usage
-----
Logging into the ahn cloud UI is handled via AT&T Foundry's APIMatrix product.

In order to log in, first authenticate using your developer account at https://apimatrix.tfoundry.com/
and then navigate to http://your.domain.com:4567/ and click log in.  This will execute an OAuth request
against APIMatrix and log you in!

