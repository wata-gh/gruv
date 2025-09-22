# frozen_string_literal: true

require 'rack/cors'
require_relative 'app'

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get options]
  end
end

run UpdateViewer::App.freeze.app
