require 'json/add/rails'
#require 'ruby-debug'
require 'yaml'

class GitpushController < ApplicationController

  def updaterally
    puts "Post content:\n"
    p JSON.parse(params["payload"]).to_yaml

    render :nothing => true, :status => 200
  end

end
