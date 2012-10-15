class DID
  include DataMapper::Resource

  property :id,         Serial
  property :created_at, DateTime

  property :number,     String
  property :app_id,     String

  def assign_to_app(app_id)
    app = App.get(app_id)
    self.app_id = app.id
    app.did = self.number
  end
end