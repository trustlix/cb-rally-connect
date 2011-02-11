require 'json/add/rails'
require 'ruby-debug'

class GitpushController < ApplicationController

  def updaterally
    puts "Post content:" + JSON.parse(params["payload"]).to_s

    render :nothing => true, :status => 200
  end

end
