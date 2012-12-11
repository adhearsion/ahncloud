class User
  include DataMapper::Resource

  property :id,         Serial
  property :created_at, DateTime

  property :username,   String, key: true
  property :token,      String
  property :enabled,    Boolean

  has n, :apps
end
