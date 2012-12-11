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
# DataMapper.auto_migrate
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
      session[:refresh_token] = body['refresh_token']
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
    tempfile = temp.path
    filename = "#{$config['rayo_routing_dir']}rayo-routing.properties"
    File.rename tempfile, filename 
    FileUtils.chmod "u=rw,g=rw,o=rw", "#{$config['rayo_routing_dir']}rayo-routing.properties"
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

  def user_has_app?(user, app)
    !!app && user.apps.include?(app)
  end
end

get '/' do
  redirect '/login' unless !!session[:user]
  @user = User.first :username => session[:user]
  unless !!@user
    @user = User.new(:username => session[:user], :token => session[:refresh_token], :created_at => Time.now, :enabled => true)
    @user.save
  end

  @apps = @user.apps
  haml :dashboard
end

get '/login' do
  haml :login
end

post '/login' do
  redirect $config['api_matrix']['login_uri'] % [$config['api_matrix']['client_id'], $config['api_matrix']['client_secret'], $config['api_matrix']['redirect_uri']]
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
      did = DID.first :number => app.did if !!app.did
      if user_has_app?(@user, app) && app.destroy
        flash[:notice] = $config['flash_notice']['app_deleted']
        update_rayo_routing
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

get 'authorize_jid' do
  content_type :json
  app = App.first :jid => params[:jid]
  options = { :body => { :client_id => $config['api_matrix']['client_id'], :client_secret => $config['api_matrix']['client_secret'], :redirect_uri => $config['api_matrix']['redirect_uri'], :grant_type => "refresh_token", :refresh_token => params[:refresh_token] } }
  if params[:refresh_token] == app.user.token
    response = HTTParty.post "https://auth.tfoundry.com/oauth/token", options
    body = JSON.parse response.body
    if body['access_token']
      { :success => true }.to_json
    else
      { :success => false }.to_json
    end
  end
end
