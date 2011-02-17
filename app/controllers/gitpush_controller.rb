require 'json/add/rails'
#require 'ruby-debug'

class GitpushController < ApplicationController

  def updaterally
    puts "Post content:\n"
    p JSON.parse(params["payload"])

    render :nothing => true, :status => 200
  end

end
