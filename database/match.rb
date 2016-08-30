class Match
  include DataMapper::Resource

  property :id,         Serial    # An auto-increment integer key
  property :date,       String

  has n, :users
end