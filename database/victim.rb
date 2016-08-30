class Victim
  include DataMapper::Resource

  property :id,         Serial    # An auto-increment integer key
  property :quake_id,   Integer

  has n, :weapons
  belongs_to :user
end