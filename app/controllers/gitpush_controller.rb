require 'json/add/rails'
require 'rally_rest_api'

class GitpushController < ApplicationController
  # require authentication
  before_filter :authenticate

  # Actions that we understand. They will cause changes to rally objects' state,
  # according to the mapping below:
  @@VALID_DEFECT_ACTIONS = {
    :none => {
      :schedule_state => "In-Progress",
      :state => "Open",
      :close_tasks => false
    },
    :fixed => {
      :schedule_state => "Completed",
      :state => "Fixed",
      :close_tasks => true
    }
  }
  @@VALID_STORY_ACTIONS = {
    :none => {
      :schedule_state => "In-Progress",
      :close_tasks => false
    },
    :completed => {
      :schedule_state => "Completed",
      :close_tasks => true
    }
  }

  def initialize(*params)
    super(*params)

    # Our rally_connector. To be initialized during authn
    @rally_connector = nil
  end

  def updaterally
    # iterate over commits and update rally objects accordingly
    cbjson = JSON.parse(params["payload"])
    cbjson["commits"].each do |commit|
      rally_defects, rally_stories = parse_commit_msg(commit["message"])

      p rally_defects
      p rally_stories
    
      commit_author = "<a href='mailto:#{commit["author"]["email"]}\
?subject=#{commit["message"]}'> #{commit["author"]["name"]} \
&lt;#{commit["author"]["email"]}&gt;</a>"
      msg = "<strong>#{commit["message"]}</strong> <a href='#{commit["url"]}' \
target='_blank'>(#{commit["id"]})</a> <br /><em>by #{commit_author} on \
#{commit["timestamp"]}</em><br /><br />"

      p msg

      # update rally objs
      update_rally_defects(rally_defects, msg)
      update_rally_stories(rally_stories, msg)
    end

    render :nothing => true, :status => 200
  end


  # Parse a commit message containing tokens in the formats:
  # [Action:USXXX], [USXXX], [Action:DEXXX] and [DEXXX]
  # XXX will be the number of Story or Deffect.
  def parse_commit_msg(msg = "")
    
    return unless not msg.empty?

    rally_defects = {}
    rally_stories = {}
    
    # TODO: there must be a better way to do this, instead of using a loop...
    # its just that I'm not a regex master! :-/
    # puts "Parsing commits:\n"
    while results = /\[(\w+:)?(US|DE)\d+\]/.match(msg)
      # split by obj type. Pattern is [{"Id"=>"Action"},...]
      if /(\w+)?:?(DE\d+)/ =~ results.to_s
        rally_defects[$2] = $1 || ""
      elsif /(\w+)?:?(US\d+)/ =~ results.to_s
        rally_stories[$2] = $1 || ""
      end
      
      # skip to next part of commit msg
      msg = results.post_match  # get the rest of the string, after the match
    end

    return rally_defects, rally_stories
  end


  # Update Rally defects based on tokens from commit msgs
  # Examples of query using rally api:
  # qr = rally.find(:defect) { equal :formatted_id, "DE12" }
  def update_rally_defects(rally_defects = {}, msg = "")
    return if (@rally_connector.nil? || rally_defects.empty? || msg.empty?)
    
    # try to find all ids at once with :fetch => true to avoid several
    # connections
    query_results = @rally_connector.find(:defect, :fetch => true) {
      _or_ {
        rally_defects.each do |id, action|
          equal :formatted_id, id
        end
      }
    }

    # OK, now we have all the defects from rally, lets update them according
    # to the actions we have configured
    query_results.each do |defect|
      ##
      # Prepare message to include as note
      note = defect.notes || ""
      msg << note

      # Update rally obj according to given action
      action = rally_defects[defect.formatted_i_d]
      if action == "" || action == nil
        action = :none
      else
        action = action.downcase.to_sym
        if not @@VALID_DEFECT_ACTIONS.has_key?(action)
          puts "Invalid action: #{action}"
          action = :none
        end
      end

      ##
      # Finally update the defect
      begin
        if @@VALID_DEFECT_ACTIONS[action][:close_tasks]
          close_tasks(defect.tasks)
        end

        defect.update(:notes => msg,
          :schedule_state => @@VALID_DEFECT_ACTIONS[action][:schedule_state],
          :state => @@VALID_DEFECT_ACTIONS[action][:state])
      rescue
        puts "Error updating defect: #{defect.name} -> #{$!}"
      end

    end
  end


  # Update Rally defects based on tokens from commit msgs
  # Examples of query using rally api:
  # qr = rally.find(:hierarchical_requirement) { equal :formatted_id, "US358" }
  def update_rally_stories(rally_stories = {}, msg = "")
    return if (@rally_connector.nil? || rally_stories.empty? || msg.empty?)
    
    query_results = @rally_connector.find(:hierarchical_requirement, 
                                          :fetch => true) {
      _or_ {
        rally_stories.each do |id, action|
          equal :formatted_id, id
        end
      }
    }

    #pp query_results
    
    query_results.each do |story|
      ##
      # Prepare message to include as note
      note = story.notes || ""
      msg << note

      # Update rally obj according to given action
      action = rally_stories[story.formatted_i_d]
      if action == "" || action == nil
        action = :none
      else
        action = action.downcase.to_sym
        if not @@VALID_STORY_ACTIONS.has_key?(action)
          puts "Invalid action: #{action}"
          action = :none
        end
      end

      ##
      # Finally update the story
      begin
        if @@VALID_STORY_ACTIONS[action][:close_tasks]
          close_tasks(story.tasks)
        end
                     
        story.update(:notes => msg, 
                     :schedule_state => @@VALID_STORY_ACTIONS[action][:schedule_state])
      rescue
        puts "Error updating story: #{story.name} -> #{$!}"
      end

    end
  end


  ##
  # Set all given tasks as completed
  def close_tasks(tasks)
    return if tasks.nil? || tasks.empty?

    tasks.each do |task|
      puts "Setting #{task.formatted_i_d} as Completed"
      task.update(:state => "Completed", :to_do => "0.0")
    end
  end


private
  

  # Get credentials and use them to authenticate user against Rally. In the
  # process we will create the connector to Rally
  def authenticate
    authenticate_or_request_with_http_basic do |id ,pass|
      # Forward authn to Rally. Use given credentials.
      begin
        custom_headers = CustomHttpHeader.new
        custom_headers.name = "CodebaseHQ to Rally Connector"
        custom_headers.version = "Alpha"
        custom_headers.vendor = "Abril Group"

        @rally_connector = RallyRestAPI.new(:username => id, :password => pass, 
                                           :http_headers => custom_headers)
      rescue
        render :nothing => true, :status => 401
      end
    end
  end

end

## Adding accessors to RestQuery's query_string attribute
#class RestQuery
#  attr_accessor :query_string
#end

