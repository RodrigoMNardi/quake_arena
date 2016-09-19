require 'sinatra'
require 'rack/throttle'
require "#{File.dirname(__FILE__)}/server"

use Rack::Throttle::Minute, :max => 60

run Q3Match