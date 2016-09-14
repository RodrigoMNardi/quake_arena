require 'sinatra'
require 'rack/throttle'
require "#{File.dirname(__FILE__)}/server"

use Rack::Throttle::Minute, :max => 30

run Q3Match