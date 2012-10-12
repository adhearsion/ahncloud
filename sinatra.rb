require 'sinatra'
require 'uuidtools'
require 'rack-flash'
require 'data_mapper'
require 'sinatra/content_for'
require 'httparty'
require 'json'

use Rack::Flash, :accessorize => [:notice, :error]
enable :sessions

require File.join(File.dirname(__FILE__), './lib', '/user.rb')
require File.join(File.dirname(__FILE__), './lib', '/app.rb')

DataMapper.setup :default, 'postgres://wdrexler@localhost/ahn_cloud_development'
DataMapper.finalize
DataMapper.auto_migrate!
# DataMapper::Model.raise_on_save_failure = true

#Temporary user creation -- Testing
User.create created_at: Time.now, username: 'wdrexler', enabled: true

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

  def authenticate
    #Stub method: waiting on API Matrix
    session[:auth] = true
    flash[:notice] = "Signed In!"
  end

  def log_out
    #Stub method: waiting on API Matrix
    session[:auth] = false
    session[:user] = nil
    flash[:notice] = "You have logged out."
  end

  def protected!
    unless authorized?
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    session[:auth] && !!session[:user]
  end

end

get '/' do
  redirect '/login' unless authorized?
  @user = User.first username: session[:user]
  @apps = @user.apps
  haml :dashboard
end

get '/login' do
  haml :login
end

post '/login' do
  session[:user] = params['Username']
  redirect 'https://auth.tfoundry.com/oauth/authorize?client_id=7919aeebf6e0d16f28d43dd427850a17&response_type=code&scope=profile&redirect_uri=http://localhost:4567/oauth/callback'
end

get '/logout' do
  log_out
  redirect '/login'
end

get '/apps/:id' do
  protected!
  @user = User.first username: session[:user]
  @app = @user.apps.get params['id']
  haml :view_app
end

get '/new_app' do
  protected!
  @user = User.first username: session[:user]
  haml :new_app
end

post '/create_app' do
  protected!
  @user = User.first :username => session[:user]
  @unique_id = UUIDTools::UUID.random_create
  @app = @user.apps.new
  @app.attributes = { :created_at => Time.now, :jid => params['Jid'], :name => params['Name'], :uuid => @unique_id.to_s, :sip_address => "#{@unique_id}@adhearsioncloud.com" }
  @app.save
  @user.save
  #Cassandra code goes here
  redirect '/'
end

get '/oauth/callback' do
  options = { :body => { :client_id => "7919aeebf6e0d16f28d43dd427850a17", :client_secret => "07f992846062c5a0", :redirect_uri => "http://localhost:4567/oauth/callback", :grant_type => "authorization_code", :code => params['code'] } }
  response = HTTParty.post "https://auth.tfoundry.com/oauth/token", options
  body = JSON.parse response.body
  if body["access_token"]
    authenticate
    redirect '/'
  else
    flash[:error] = "Failed to authenticate user"
    redirect '/login'
  end
end