require 'sinatra'
require 'uuidtools'
require 'rack-flash'
require 'data_mapper'
require 'sinatra/content_for'
require 'httparty'
require 'json'
require 'xmpp4r'
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'etc'

YAML::ENGINE.yamler = 'syck'
use Rack::Flash, :accessorize => [:notice, :error]
enable :sessions
set :environment, :production

require File.join(File.dirname(__FILE__), './lib', '/user.rb')
require File.join(File.dirname(__FILE__), './lib', '/app.rb')
require File.join(File.dirname(__FILE__), './lib', '/did.rb')
require File.join(File.dirname(__FILE__), './lib', '/jabber_process.rb')

$config = YAML.load_file(File.join(File.dirname(__FILE__), './config', '/config.yml'))


DataMapper.setup :default, $config['postgres_db']
DataMapper.finalize
DataMapper.auto_upgrade!
# DataMapper::Model.raise_on_save_failure = true

helpers do

  def show_flash
    if flash[:notice]
      { :method => "notice", :message => flash[:notice] }
    elsif flash[:error]
      { :method => "error", :message => flash[:error] }
    else
      { :method => "", :message => "" }
    end
  end

  def authenticate(code)
    options = { :body => { :client_id => $config['api_matrix']['client_id'], :client_secret => $config['api_matrix']['client_secret'], :redirect_uri => $config['api_matrix']['redirect_uri'], :grant_type => "authorization_code", :code => code } }
    response = HTTParty.post "https://auth.tfoundry.com/oauth/token", options
    body = JSON.parse response.body
    if body['access_token']
      session[:access_token] = body['access_token']
      redirect '/login' unless authorized?
      flash[:notice] = $config['flash_notice']['log_in'] % session[:user]
      redirect '/'
    else
      flash[:error] = $config['flash_error']['auth_failed']
      redirect '/login'
    end
  end

  def log_out
    session[:access_token] = nil
    session[:user] = nil
  end

  def authorized?
    response = HTTParty.get $config['api_matrix']['auth_uri'] % session[:access_token]
    body = JSON.parse response.body
    if body["error"]
      session[:user] = nil
      session[:access_token] = nil
      flash[:error] = $config['flash_error']['auth_failed']
      false
    else
      session[:user] = body["email"]
      true
    end
  end

  def update_rayo_routing
    temp = Tempfile.new "rayo-routing", $config['rayo_routing_dir']
    App.all.each do |app|
      temp << ".*#{app.sip_address}.*=#{app.jid}\n"
      temp << ".*#{app.did}.*=#{app.jid}\n" if !!app.did
    end
    temp.close false
    filename = temp.path
    File.rename filename, "#{$config['rayo_routing_dir']}rayo-routing.properties"
    File.chown(Etc.getpwnam("voxeo").uid, Etc.getgrnam("ahncloud").gid, filename)
    FileUtils.chmod "u=rw,g=rw,o=r", "#{$config['rayo_routing_dir']}rayo-routing.properties"
  end

  def assign_did(app_id)
    if authorized?
      user = User.first :username => session[:user]
      app = App.get app_id
      if app && user.apps.include?(app)
        if DID.first
          DID.all.each do |d|
            if d.app_id.nil?
              d.app_id = app.id
              app.did = d.number
              d.save
              break
            end
          end
        else
          flash[:error] = $config['flash_error']['did_assign_failed'] % app.name
          redirect '/'
        end
        app.save
        if app.did
          update_rayo_routing
          flash[:notice] = $config['flash_notice']['did_assigned'] % [app.did, app.name]
        else
          flash[:error] = $config['flash_error']['did_assign_failed'] % app.name
        end
      else
        flash[:error] = $config['flash_error']['app_not_found']
      end
    else
      flash[:error] = $config['flash_error']['auth_failed']
    end
    redirect '/'
  end

  def change_jid_password(jid, old_password, new_password)
    client = Jabber::Client.new jid
    client.connect
    client.auth old_password
    client.password = new_password
    client.close
  end

  def unregister_jid(jid, password)
    client = Jabber::Client.new jid
    client.connect
    client.auth password
    client.remove_registration
    client.close
  end

  def user_has_app?(user, app)
    !!app && user.apps.include?(app)
  end
end

get '/' do
  redirect '/login' unless !!session[:user]
  @user = User.first :username => session[:user]
  unless !!@user
    @user = User.new(:username => session[:user], :created_at => Time.now, :enabled => true)
    @user.save
  end

  @apps = @user.apps
  haml :dashboard
end

get '/login' do
  haml :login
end

post '/login' do
  redirect $config['api_matrix']['login_uri']
end

get '/logout' do
  log_out
  flash[:notice] = $config['flash_notice']['log_out']
  redirect '/login'
end


get '/new_app' do
  @user = User.first :username => session[:user]
  haml :new_app
end

post '/create_app' do
  if authorized?
    @user = User.first :username => session[:user]
    @unique_id = UUIDTools::UUID.random_create
    @app = @user.apps.new
    @app.attributes = { :created_at => Time.now, :jid => "#{@unique_id}@#{$config['ejabberd_host']}", :name => params['Name'], :uuid => @unique_id.to_s, :sip_address => "#{@unique_id}@#{$config['prism_host']}", :did => nil, :status => "Incomplete" }
    @app.save
    @user.save
    process = JabberProcess.new :created_at => Time.now, :jid => @app.jid, :password => params['Password'], :app_id => @app.id
    process.save
    update_rayo_routing
    flash[:notice] = $config['flash_notice']['app_created'] % @app.name
    redirect '/'
  else
    redirect '/login'
  end
end

get '/delete_app' do
  @app_id = params['app_id']
  @app = App.get @app_id
  haml :delete_app
end

post '/delete_app' do
  if authorized?
    @user = User.first :username => session[:user]
    if params['app_id']
      app = App.get params['app_id']
      jid = app.jid
      did = DID.first :number => app.did
      begin
        unregister_jid(jid, params['Password'])
      rescue
        flash[:error] = "Jabber Authentication Error. Please try again."
        redirect '/'
      end
      if user_has_app?(@user, app) && app.destroy
        flash[:notice] = $config['flash_notice']['app_deleted']
      else
        flash[:error] = $config['flash_error']['app_not_found']
      end
    else
      flash[:error] = $config['flash_error']['app_not_found']
    end
  else
    flash[:error] = $config['flash_error']['auth_failed']
    log_out
  end
  update_rayo_routing
  redirect '/'
end

get '/edit_jid_password' do
  if params['app_id']
    @app_id = params['app_id']
    @app = App.get @app_id
    if @app
      haml :edit_password
    else
      flash[:error] = $config['flash_error']['app_not_found']
      redirect '/'
    end
  else
    flash[:error] = $config['flash_error']['app_not_found']
    redirect '/'
  end
end

post '/edit_jid_password' do
  if authorized?
    @user = User.first :username => session[:user]
    app = App.get params['app_id']
    if params['old_password'] && params['new_password'] && user_has_app?(@user, app)
      if change_jid_password app.jid, params['old_password'], params['new_password']
        flash[:notice] = "Password successfully changed for App #{app.name}"
      else
        flash[:error] = "There was an error changing the password, please try again later."
      end
      redirect '/'
    else
      flash[:error] = "Invalid input. Please try again."
      redirect '/edit_jid_password'
    end
  else
    redirect '/'
  end
end


get '/edit_name' do
  if params['app_id']
    @app_id = params['app_id']
    @app = App.get @app_id
    if @app
      haml :edit_name
    else
      flash[:error] = $config['flash_error']['app_not_found']
      redirect '/'
    end
  else
    flash[:error] = $config['flash_error']['app_not_found']
    redirect '/'
  end
end

post '/edit_name' do
  if authorized?
    @user = User.first :username => session[:user]
    if params['app_id']
      app = App.get params['app_id']
      if user_has_app?(@user, app)
        app.update :name => params['Name']
        flash[:notice] = $config['flash_notice']['name_updated'] % app.name
      else
        flash[:error] = $config['flash_error']['app_not_found']
      end
    else
      flash[:error] = $config['flash_error']['app_not_found']
    end
  else
    log_out
  end
  redirect '/'
end

get '/assign_did' do
  assign_did params['app_id']
end

get '/oauth/callback' do
  authenticate(params['code'])
end
