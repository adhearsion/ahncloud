class JabberProcess
  include DataMapper::Resource

  property :id,         Serial
  property :created_at, DateTime

  property :app_id,     String
  property :jid,        String, :length => 255
  property :password,   String
end