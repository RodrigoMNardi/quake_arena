require "#{File.dirname(__FILE__)}/database"
require  'dm-migrations'

DataMapper.auto_migrate!

