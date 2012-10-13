class App
  include DataMapper::Resource

  property :id,          Serial
  property :created_at,  DateTime

  property :uuid,        String 
  property :jid,         String
  property :sip_address, String, :length => 255
  property :name,        String
  property :did_active,  Boolean

  belongs_to :user
end