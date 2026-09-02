# frozen_string_literal: true

require 'json'
require 'sinatra/base'

module SLA
  class App < Sinatra::Base
    set :root, File.expand_path('../..', __dir__)
    set :views, File.join(root, 'views')

    get '/healthz' do
      content_type :json
      JSON.generate(ok: true)
    end
  end
end
