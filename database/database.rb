require 'data_mapper'
require 'dm-validations'
require "#{File.dirname(__FILE__)}/user"
require "#{File.dirname(__FILE__)}/weapon"
require "#{File.dirname(__FILE__)}/victim"
require "#{File.dirname(__FILE__)}/killer"
require "#{File.dirname(__FILE__)}/match"

DataMapper::Logger.new($stdout, :info)
DataMapper.setup(:default, "sqlite://#{File.dirname(__FILE__)}/quake_parks.db")

DataMapper.finalize


