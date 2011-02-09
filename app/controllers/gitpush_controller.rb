class GitpushController < ApplicationController

  def updaterally
    p params

    render :nothing => true, :status => 200
  end

end
