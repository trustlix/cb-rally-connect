require 'rally_rest_api'

class RallyConnector
  
  attr_accessor :username, :password, :custom_headers
  attr_reader :conn, :workspace

  def initialize(options = {})
    @username = options[:username] || CONFIG['rally_username']
    @password = options[:password] || CONFIG['rally_password']

    if options[:custom_headers]
      @custom_headers = options[:custom_headers]
    else
      @custom_headers = CustomHttpHeader.new
      @custom_headers.name = CONFIG['custom_headers']['name']
      @custom_headers.version = CONFIG['custom_headers']['version']
      @custom_headers.vendor = CONFIG['custom_headers']['vendor']
    end
    
    @conn = nil
  end

  
  def connect
    Rails.logger.info("RallyConnector::connect\n" + 
                      "\tusername: #{@username}\n"+
                      "\tpassword: #{@password}\n"+
                      "\tcustom headers: #{@custom_headers.to_s}")
    begin
      @conn = RallyRestAPI.new(:username => @username, 
                               :password => @password,
                               :http_headers => @custom_headers)
      @workspace = find_workspace(CONFIG['rally_workspace'])
      return @conn
    rescue => e 
      Rails.logger.info( "Could not connect to Rally: #{e.to_s}" )
      return nil
    end
  end
  
  
  def create_rally_obj(type, params)
    return nil unless (type and params)

    ret = nil
    begin
      ret = @conn.create(type, params)
    rescue => e
      Rails.logger.error("Can't create Rally object #{type}: #{e.to_s}")
    end

    return ret
  end
  

  def update_rally_obj(obj, params)
    ret = nil
    begin
      ret = obj.update(params)
    rescue => e
      Rails.logger.error("Can't update Rally object #{type}: #{e.to_s}")
    end

    return ret

  end

  def to_s
    return "Connected: #{@conn != nil ? "Yes" : "No"} - " + 
      "Username: #{@username}, Password: #{@password}"
  end

  def is_build_flag_enabled?()
    begin
      return true if @workspace.workspace_configuration.buildand_changeset_enabled == 'true'

      Rails.logger.error("Enable build and changeset in your workspace")
      return false
    rescue => e
      Rails.logger.error("Can't fetch build_and_changeset status: #{e.to_s}")
      return false
    end
  end

  def find_workspace(workspace_name = nil)
    return nil unless (workspace_name and @conn)

    begin
      workspace = @conn.user.subscription.workspaces.find { |w|
        w.name == workspace_name && w.state == 'Open'
      }
    
      raise "Couldn't find workspace #{workspace_name}" if workspace.nil?

      return workspace
    rescue => e
      Rails.logger.error("\n#{e.to_s}")
      return nil
    end
  end

  def get_possible_attribute_values(artifact_type_name = nil, attribute_name = nil)
    return [] unless (artifact_type_name and attribute_name and @conn)

    Rails.logger.info("Fetching available states for: #{artifact_type_name}")

    attrs = @conn.find(
      :type_definition, 
      :fetch => true, 
      :workspace => @workspace) { equal :name, artifact_type_name }.results[0].attributes

    values = attrs.find { |v| v.name == attribute_name }.allowed_values

    ret = []
    values.each { |v| ret.push(v.string_value) }

    Rails.logger.info("Values found for attribute #{attribute_name}: #{ret}")

    return ret
  end

  def find(options)
    type = options[:type] || :hierarchical_requirement
    field = options[:field] || :formatted_i_d
    values = options[:values] || []

    begin
      return nil unless (type and field and (values.length > 0) and @conn)

      ret = @conn.find(type, :workspace => @workspace, :fetch => true) {
        _or_ {
          values.each do |v|
            equal field, v.to_s
          end
        }
      }
      
      return ret.results if ret.total_result_count.to_i > 0
      return []
    rescue => e
      Rails.logger.error("Can't find (#{type}, #{field}, #{values}) in #{@workspace}")
      return []
    end
  end

end
