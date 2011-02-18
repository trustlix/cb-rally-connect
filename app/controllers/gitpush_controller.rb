require 'json/add/rails'

class GitpushController < ApplicationController
  # require authentication
  before_filter :authenticate

  def updaterally
    # iterate over commits and update rally objects accordingly
    cbjson = JSON.parse(params["payload"])
    cbjson["commits"].each do |commit|
      puts "Parsing commits:\n"
      pp parse_commit_msg(commit["message"])
    end

    render :nothing => true, :status => 200
  end

  def parse_commit_msg(msg = "")
    return unless msg.empty?
    
    # we support basically USXXX (User Story) and DEXXX (Defect) types of Rally
    # objects.
    # Current supported syntax is:
    # [USXXX: Action] and [DEXXX: Action], where XXX is the number of the story
    # or defect. The actions will be treated elsewhere, so no need to worry now.
    #
    # TODO: there must be a better way to do this, instead of using a loop...
    # its just that I'm not a regex master! :-/
    rally_obj_refs = []
    while results = /(\[US|DE\d+(:\s\w+)?\])/.match(msg)
      rally_obj_refs << results.to_s
      msg = results.post_match  # get the rest of the string, after the match
    end

    return rally_obj_refs
  end

  def is_defect?(rally_obj_ref = "")
    return /DE\d+/ =~ rally_obj_ref

  end

  def update_rally_defect

  end

private

  def authenticate
    authenticate_or_request_with_http_basic do |id ,pass|
      # TODO: Forward authn to Rally. Use given credentials.
      id == "Alex" && pass == "123456"
    end
  end

end
