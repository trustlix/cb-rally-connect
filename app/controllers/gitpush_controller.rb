require 'json/add/rails'

class GitpushController < ApplicationController
  # require authentication
  before_filter :authenticate

  def initialize(*params)
    super(*params)

    # rally defects from post
    @rally_defects = {}

    # rally stories from post
    @rally_stories = {}
    
    # Our rally_connector. To be initialized during authn
    @rally_connector = nil
  end

  def updaterally
    # iterate over commits and update rally objects accordingly
    cbjson = JSON.parse(params["payload"])
    cbjson["commits"].each do |commit|
      parse_commit_msg(commit["message"])
    end

    @rally_defects.each do |id, action|
      puts "ID: #{id} - Action: #{action}"
    end
    @rally_stories.each do |id, action|
      puts "ID: #{id} - Action: #{action}"
    end

    render :nothing => true, :status => 200
  end

  # Parse a commit message containing tokens in the formats:
  # [US: XXX], [USXXX], [DEXXX] and [DE]
  # XXX will be the number of Story or Deffect.
  def parse_commit_msg(msg = "")
    
    return unless not msg.empty?
    
    # TODO: there must be a better way to do this, instead of using a loop...
    # its just that I'm not a regex master! :-/
    # puts "Parsing commits:\n"
    while results = /(\[(US|DE)\d+(:\s\w+)?\])/.match(msg)
      # split by obj type. Pattern is [{"Id"=>"Action"},...]
      if /(DE\d+)(:\s*)?(\w+)?/ =~ results.to_s
        @rally_defects[$1] = $3 || ""
      elsif /(US\d+)(:\s*)?(\w+)?/ =~ results.to_s
        @rally_stories[$1] = $3 || ""
      end
      
      # skip to next part of commit msg
      msg = results.post_match  # get the rest of the string, after the match
    end

  end

  # Update Rally defects based on tokens from commit msgs
  def update_rally_defects
    return unless not @rally_defects.empty?
    return unless not @rally_connector.nil?


  end

  # Update Rally stories based on tokens from commit msgs
  def update_rally_stories
    return unless not @rally_defects.empty?
    return unless not @rally_connector.nil?
  end

private
  
  # Get credentials and use them to authenticate user against Rally. In the
  # process we will create the connector to Rally
  def authenticate
    authenticate_or_request_with_http_basic do |id ,pass|
      # Forward authn to Rally. Use given credentials.
      begin
        @rally_connector = RallyRestAPI.new(:username => id, :password => pass)
      rescue
        render :nothing => true, :status => 401
      end
    end
  end

end
