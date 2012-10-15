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
require File.join(File.dirname(__FILE__), './lib', '/did.rb')


DataMapper.setup :default, 'postgres://wdrexler@localhost/ahn_cloud_development'
DataMapper.finalize
DataMapper.auto_migrate!
# DataMapper::Model.raise_on_save_failure = true


#Temporary fake DIDs for testing
DID.new(:created_at => Time.now, :number => "123456", :app_id => nil).save
DID.new(:created_at => Time.now, :number => "323417", :app_id => nil).save
DID.new(:created_at => Time.now, :number => "8675309", :app_id => nil).save

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
    session[:access_token] = nil
    session[:user] = nil
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

  def update_rayo_routing
    rayo_routing_properties = File.new(File.join(File.dirname(__FILE__), './config', '/rayo-routing.properties'), 'w')
    App.all.each do |app|
      rayo_routing_properties.write ".*#{app.sip_address}.*=#{app.jid}\n"
      rayo_routing_properties.write ".*#{app.did}.*=#{app.jid}\n" if !!app.did
    end
    rayo_routing_properties.close
  end

  def assign_did(app_id)
    if authorized?
      user = User.first :username => session[:user]
      app = App.get app_id
      if app && user.apps.include?(app)
        DID.all.each do |d|
          if d.app_id.nil?
            d.app_id = app.id
            app.did = d.number
            d.save
            break
          end
        end
        app.save
        if app.did
          flash[:notice] = "DID #{app.did} added to App #{app.name}"
        else
          flash[:error] = "Could not assign DID. Please try again later."
        end
      else
        flash[:error] = "App not found."
      end
    else
      flash[:error] = "Unauthorized User."
    end
    redirect '/'
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
  redirect 'https://auth.tfoundry.com/oauth/authorize?client_id=7919aeebf6e0d16f28d43dd427850a17&client_secret=07f992846062c5a0&response_type=code&scope=profile&redirect_uri=http://localhost:4567/oauth/callback'
end

get '/logout' do
  log_out
  flash[:notice] = "You have logged out."
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
    @app.attributes = { :created_at => Time.now, :jid => "#{@unique_id}@ahncloudim.tfoundry.com", :name => params['Name'], :uuid => @unique_id.to_s, :sip_address => "#{@unique_id}@ahncloudprism.tfoundry.com", :did => nil }
    @app.save
    @user.save
    update_rayo_routing
    redirect '/'
  else
    redirect '/login'
  end
end

get '/delete_app' do
  if authorized?
    @user = User.first :username => session[:user]
    if params['app_id']
      app = App.get params['app_id']
      did = DID.first :number => app.did
      if app && @user.apps.include?(app)
        if app.destroy
          did.app_id = nil
          did.save
          flash[:notice] = "App sucessfully deleted"
        else
          flash[:error] = "Error: #{app.errors.each {|e| e.to_s}}"
        end
      else
        flash[:error] = "Error: App Not Found"
      end
    else
      flash[:error] = "Error: No App ID Specified"
    end
  else
    flash[:error] = "Unauthorized User"
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
      flash[:error] = "Error: App Not Found"
      redirect '/'
    end
  else
    flash[:error] = "Error: No App ID Specified"
    redirect '/'
  end
end

post '/edit_name' do
  if authorized?
    @user = User.first :username => session[:user]
    if params['app_id']
      app = App.get params['app_id']
      if app && @user.apps.include?(app)
        app.update :name => params['Name']
        flash[:notice] = "Name Updated for App #{app.name}"
      else
        flash[:error] = "Error: Unable to find App"
      end
    else
      flash[:error] = "Error: No App ID Specified"
    end
  else
    flash[:error] = "Unauthorized User"
  end
  redirect '/'
end

get '/assign_did' do
  assign_did params['app_id']
end

get '/oauth/callback' do
  authenticate(params['code'])
end