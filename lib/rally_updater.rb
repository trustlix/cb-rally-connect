#require 'rally_connector'
#require 'codebase_connector'

class RallyUpdater
  attr_reader :rally_connector, :update_schedule_state, :update_states,
    :update_owner

  def initialize(options)
    @rally_connector = options[:rally_connector] || nil
    @update_schedule_state = options[:update_schedule_state] || true
    @update_states = options[:update_states] || true
    @update_owner = options[:update_owner] || true
  end

  def update_rally_artifacts(cb_push = nil)
    return false unless (cb_push and @rally_connector)

    ##
    # make sure we have a Repository object in rally that matches the one
    # related to this push
    repository = get_scm_repository(cb_push)
    if repository.nil?
      Rails.logger.info("Couldn't create repository. Changesets won't be \
                        created as well.")
    else
      Rails.logger.info("Using SCMRepository: #{repository}")
    end

    ##
    # handle stories and defects found on each commit's msg
    cb_push.commits.each do |c|
      Rails.logger.info("Handling commit: #{c.id}")

      ##
      # no tokens to handle, jump to next commit
      if c.rally_artifact_tokens['US'].nil? and c.rally_artifact_tokens['DE'].nil?
        Rails.logger.info("No tokens found in commit's message")
        next
      end

      ##
      # find rally artifacts
      stories = []
      defects = []
      if ! c.rally_artifact_tokens['US'].nil?
        story_ids  = c.rally_artifact_tokens["US"].keys
        stories = @rally_connector.find(:values => story_ids)
      else
        Rails.logger.info("No story tokens found")
      end
      
      if ! c.rally_artifact_tokens['DE'].nil?
        defect_ids = c.rally_artifact_tokens["DE"].keys
        defects = @rally_connector.find(:type => :defect, 
                                        :field => :formatted_i_d, 
                                        :values => defect_ids)
      else
        Rails.logger.info("No defect tokens found")
      end
      
      artifacts = stories | defects

      ##
      # Try to find a Rally user corresponding to this commit's author
      rally_user = get_rally_user(c)

      ##
      # For each commit we might have a changeset. Create it, then append all
      # the changes made in the commit
      cs = create_rally_changeset(c, rally_user, repository, artifacts)
      create_rally_changes(c, cs)

      ##
      # Finally update the artifacts
      if ! stories.empty?
        #update stories
        stories.each { |s|
          Rails.logger.info("Updating #{s.formatted_i_d}")
          update_rally_story(c, s, cs)
          create_discussion_msg(s, c)
        }
      else
        Rails.logger.info("Stories not found in Rally")
      end

      if ! defects.empty?
        defects.each { |d|
          Rails.logger.info("Updating #{d.formatted_i_d}")
          update_rally_defec(c, d, cs, rally_user)
          create_discussion_msg(d, c)
        }
      else
        Rails.logger.info("Defects not found in Rally")
      end
    end

    return true
  end

  ##
  #
  #
  def update_rally_story(commit, story, changeset)
    schedule_state = @rally_connector.check_schedule_state(
      commit.rally_artifact_tokens['US'][story.formatted_i_d])

    options = {}
    options[:changeset] = changeset unless changeset.nil?
    options[:schedule_state] = schedule_state unless schedule_state.nil?
    
    Rails.logger.info("Updating story: #{story.formatted_i_d}, options: #{options}")

    @rally_connector.update_rally_obj(story, options)
  end
  
  ##
  #
  #
  def update_rally_defec(commit, defect, changeset, user)
    state = @rally_connector.check_defect_state(
      commit.rally_artifact_tokens['DE'][defect.formatted_i_d])

    options = {}
    options[:changeset] = changeset unless changeset.nil?
    options[:state] = state unless state.nil?
    options[:owner] = user.ref unless user.nil?
    
    Rails.logger.info("Updating defect: #{defect.formatted_i_d}, options: #{options}")

    return @rally_connector.update_rally_obj(defect, options)
  end

  ##
  #
  #
  def create_rally_changeset(commit, user, repository, artifacts)
    return nil if (repository.nil? or artifacts.nil?)

    # try to parse timestamp from commit. Fallback to current time on error
    begin
      commit_timestamp = Time.parse(commit.timestamp).utc.xmlschema
    rescue => e
      Rails.logger.info("Error parsing date: #{e}. Using current date instead.")
      commit_timestamp = Time.now.utc.xmlschema
    end

    cs_options = { :workspace => @rally_connector.workspace.ref, 
      :revision => commit.id, :commit_timestamp => commit_timestamp, 
      :uri => commit.url, :s_c_m_repository => repository, 
      :message => commit.msg.slice(0,3999), :artifacts => artifacts }
    cs_options["author"] = user unless user.nil?

    return @rally_connector.create_rally_obj(:changeset, cs_options)
  end

  ##
  #
  #
  def create_rally_changes(commit, changeset)
    return [] if commit == nil || changeset == nil
    
    Rails.logger.info("Creating changes")

    changes = []
    commit.files_changed.each { |action, files|
      files.each { |file|
        change = @rally_connector.create_rally_obj(:change, {
          :action => action, :extension => file[:extension], 
          :path_and_filename => file[:path], :changeset => changeset})
          changes.push(change)
      }
    }

    Rails.logger.info("Created changes: #{changes}")
    
    return changes
  end

  ##
  #
  #
  def get_scm_repository(cb_push = nil)
    ##
    # make sure we have a Repository object in rally that matches the one
    # related to this push
    repository = @rally_connector.find_repository(cb_push.repository)
    if repository.nil?
      Rails.logger.info("Couldn't find scm_repo. Trying to create one")
      repository = @rally_connector.create_rally_obj(:s_c_m_repository, {
        :workspace => @rally_connector.workspace.ref,
        :name => cb_push.repository,
        :descriptor => "Codebase repository. #{cb_push.repository}",
        :uri => cb_push.repository_url,
        :s_c_m_type => "Rally2Codebase Connector" 
      })
    end

    return repository
  end

  ##
  #
  #
  def create_discussion_msg(artifact = nil, commit = nil)
    return nil unless (artifact and commit)

    msg = commit.msg.slice(0,32767)
    if not commit.author.nil?
      msg = "Commit made by <b>#{commit.author["email"]}</b> [#{commit.id}][#{commit.timestamp}]<br/>#{msg}"
    end

    conversation_post = @rally_connector.create_rally_obj(:conversation_post, {
      :workspace => @rally_connector.workspace.ref,
      :artifact => artifact.ref,
      :text => msg
    })

    return conversation_post
  end

  ##
  # Try to find a Rally user corresponding to this commit's author
  #
  def get_rally_user(commit)
    if (commit and commit.author and commit.author.key?("email"))
      return @rally_connector.find_user(commit.author["email"])
    end

    return nil
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

end
