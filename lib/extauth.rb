#!/usr/bin/ruby
# ejabberd external authentication script
# WARNING: This script provides no security! It simply validates that the username is numeric
# and then trusts that the user is valid.
# See: https://git.process-one.net/ejabberd/mainline/blobs/raw/2.1.x/doc/dev.html#htoc8
require 'logger'
require 'httparty'
require 'json'

# Ruby 1.8 uses 'n' to indicate a short in network order
# Ruby 1.9 uses 'S>'
PACK_FORMAT = RUBY_VERSION =~ /^1\.9/ ? 'S>' : 'n'

log = Logger.new "/var/log/ejabberd/extauth.log"
log.level = Logger::INFO
log.info "External authentication script starting up!"

$stdout.sync = true

def response(pass = false)
  [2,pass ? 1 : 0].pack("#{PACK_FORMAT}#{PACK_FORMAT}")
end

def authorize(input = nil)
  unless input $stdout.write response false
  response = HTTParty.get "https://auth.tfoundry.com/me.json?access_token=%s" % input 
  body = JSON.parse response.body
  if body["error"]
    log.info "Token #{input} rejected!"
    $stdout.write response(false)
  else
    log.info "Token #{input} authenticated"
    $stdout.write response(true)
  end
end

begin
  loop do
    # Read the length of coming data. Length is sent as a short in network byte order.
    log.debug 'entered loop'
    len = $stdin.read(2).unpack(PACK_FORMAT).first
    log.debug "Expecting #{len} bytes..."
    # Read that many bytes from stdin and split on colon delimeter
    input = $stdin.read(len)
    log.debug "Read data: #{input.inspect}"
  
    authorize input
  end
rescue => e
  log.error "Rescued exception! #{e.message}"
  log.debug e.backtrace.join "\n"
  exit 1
end
