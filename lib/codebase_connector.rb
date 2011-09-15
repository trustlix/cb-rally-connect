require 'json'
require 'ruby-debug'

class CodebasePush

  attr_reader :commits, :repository

  def initialize(codebase_push_json = nil)
    @codebase_json = codebase_push_json
    @commits = parse_commits

    if @codebase_json.key?("repository") and 
      @codebase_json["repository"].key?("name")
      @repository = @codebase_json["repository"]["name"]
    else
      @repository = nil
    end

  end

  private

  def parse_commits
    return [] unless (@codebase_json and @codebase_json.key?("commits"))
    
    commits = []
    @codebase_json["commits"].each do |c|
      commits.push(CodebaseCommit.new(c))
    end

    return commits
  end

end # CodebasePush


class CodebaseCommit

  ##
  # get valid changes from global config
  VALID_CHANGES = CONFIG["codebase_valid_file_changes"] || []

  attr_reader :raw_commit, :rally_artifact_tokens, :files_changed, :id,
              :timestamp, :url, :author, :msg

  def initialize(codebase_commit_json = nil)
    @raw_commit = codebase_commit_json
    
    @id = (@raw_commit and @raw_commit.key?("id")) ? @raw_commit["id"] : nil
    @author = (@raw_commit and @raw_commit.key?("author")) ? @raw_commit["author"] : nil
    @msg = (@raw_commit and @raw_commit.key?("message")) ? @raw_commit["message"] : nil
    @timestamp = (@raw_commit and @raw_commit.key?("timestamp")) ? @raw_commit["timestamp"] : nil
    @url = (@raw_commit and @raw_commit.key?("url")) ? @raw_commit["url"] : nil
    
    @rally_artifact_tokens = get_artifact_tokens_from_msg
    @files_changed = get_modified_files
  end
  
  private

  def get_modified_files
    return {} unless @raw_commit

    modified_files = {}
    VALID_CHANGES.each do |a|
      modified_files[a] = []
      @raw_commit[a].each do |file|
        modified_files[a].push({:path => file, 
                               :extension => File.extname(file)})
      end
    end
    return modified_files
  end

  ##
  # Parse the messages from an array of commits, looking for tokens in the form:
  # [State:AA000], [AA000], where:
  #  - State is a string determining the state we should set for the given
  #     artifact
  #  - AA is the artifact's descriptor in Rally
  #  - 0000 is the artifact's id in Rally
  def get_artifact_tokens_from_msg
    return {} unless (@raw_commit and @raw_commit.key?("message"))

    tokens = {}

    matches = msg.scan(/\[(\w+:)?(\S\S)(\d+)\]/)
    matches.each do |token|
      # token[0] -> state
      # token[1] -> artifact descriptor
      # token[2] -> artifact id

      next unless (token[1] and token[2]) # required data

      # initialize array for every new artifact type, then populate it
      tokens[token[1]] = [] unless tokens.key?(token[1])
      tokens[token[1]].push({:id => token[1]+token[2], :state => token[0]})
    end

    return tokens
  end

end # CodebaseCommit
