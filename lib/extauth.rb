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
  command = input[0]
  unless (input && command == 'auth') $stdout.write response false
  response = HTTParty.get "https://ahncloudprism.tfoundry.com/authorize_jid?jid=%s&refresh_token=%s" % [input[1], input[2]] 
  body = JSON.parse response.body
  if body["success"] == "true"
    log.info "Token #{input[2]} authenticated"
    $stdout.write response(true)
  else
    log.info "Token #{input[2]} rejected!"
    $stdout.write response(false)
  end
end

begin
  loop do
    # Read the length of coming data. Length is sent as a short in network byte order.
    log.debug 'entered loop'
    len = $stdin.read(2).unpack(PACK_FORMAT).first
    log.debug "Expecting #{len} bytes..."
    # Read that many bytes from stdin and split on colon delimeter
    input = $stdin.read(len).split ":"
    log.debug "Read data: #{input.inspect}"
  
    authorize input
  end
rescue => e
  log.error "Rescued exception! #{e.message}"
  log.debug e.backtrace.join "\n"
  exit 1
end
