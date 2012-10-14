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
    options = { :body => { :client_id => "7919aeebf6e0d16f28d43dd427850a17", :client_secret => "07f992846062c5a0", :redirect_uri => "http://localhost:4567/oauth/callback", :grant_type => "authorization_code", :code => code } }
    response = HTTParty.post "https://auth.tfoundry.com/oauth/token", options
    body = JSON.parse response.body
    if body['access_token']
      session[:access_token] = body['access_token']
      redirect '/login' unless authorized?
      flash[:notice] = "Signed In! Welcome, #{session[:user]}"
      redirect '/'
    else
      flash[:error] = "Failed to authenticate user"
      redirect '/login'
    end
  end

  def log_out
    #Stub method: waiting on API Matrix
    session[:access_token] = nil
    session[:user] = nil
    flash[:notice] = "You have logged out."
  end

  def authorized?
    response = HTTParty.get "https://auth.tfoundry.com/me.json?access_token=#{session[:access_token]}"
    body = JSON.parse response.body
    if body["error"]
      session[:user] = nil
      session[:access_token] = nil
      flash[:error] = "Failed to authenticate user"
      false
    else
      session[:user] = body["email"]
      true
    end
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
  redirect 'https://auth.tfoundry.com/oauth/authorize?client_id=7919aeebf6e0d16f28d43dd427850a17&response_type=code&scope=profile&redirect_uri=http://localhost:4567/oauth/callback'
end

get '/logout' do
  log_out
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
    @app.attributes = { :created_at => Time.now, :jid => params['Jid'], :name => params['Name'], :uuid => @unique_id.to_s, :sip_address => "#{@unique_id}@adhearsioncloud.com", :did_active => false }
    @app.save
    @user.save
    redirect '/'
  else
    redirect '/login'
  end
end

get '/delete_app' do
  @user = User.first :username => session[:user]
  if params['app_id']
    app = App.get(params['app_id'])
    if app && @user.apps.include?(app)
      if app.destroy
        flash[:notice] = "App sucessfully deleted"
      else
        flash[:error] = "Error: #{app.errors.each {|e| e.to_s}}"
      end
    else
      flash[:error] = "Error: App Does Not Exist"
    end
  else
    flash[:error] = "Error: No App ID Specified"
  end
  redirect '/'
end

get '/oauth/callback' do
  authenticate(params['code'])
end