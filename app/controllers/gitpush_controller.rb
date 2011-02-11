require 'json/add/rails'

class GitpushController < ApplicationController

  def updaterally
    puts JSON.parse params["payload"]

    render :nothing => true, :status => 200
  end

end
