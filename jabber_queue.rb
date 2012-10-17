require 'xmpp4r'
require 'data_mapper'
require 'yaml'

YAML::ENGINE.yamler = 'syck'

require File.join(File.dirname(__FILE__), './lib', '/jabber_process.rb')
require File.join(File.dirname(__FILE__), './lib', '/app.rb')
require File.join(File.dirname(__FILE__), './lib', '/user.rb')

def register_jid(jid, password)
  client = Jabber::Client.new jid
  client.connect
  client.register password
  client.close
end

$config = YAML.load_file(File.join(File.dirname(__FILE__), './config', '/config.yml'))

DataMapper.setup :default, $config['postgres_db']
DataMapper.finalize
DataMapper.auto_upgrade!

while true
  if JabberProcess.first
    failed = false
    @procs_by_creation_time = JabberProcess.all :order => [ :created_at.asc ]
    process = @procs_by_creation_time.first
    app = App.get process.app_id
    begin
      register_jid process.jid, process.password
    rescue
      failed = true
    end
    unless failed
      app.status = "Ready"
      app.save
      process.destroy
    end
    sleep 20
  end
end