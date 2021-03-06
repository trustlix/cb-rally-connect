# require 'json/add/rails'
require 'json'
require 'rally_rest_api'
require 'lib/rally_updater'
require 'lib/codebase_connector'

class GitpushController < ApplicationController
  # require authentication
  # before_filter :authenticate

  def initialize(*params)
    super(*params)
  end

  def updaterally
    Rails.logger.info(params)
    cbjson = JSON.parse(params["payload"])
    cbpush = CodebasePush.new(cbjson)
    rupdater = RallyUpdater.new(:rally_connector => RALLY_CONNECTOR,
                                :update_owner => false)
    rupdater.update_rally_artifacts(cbpush)

    render :nothing => true, :status => 200
  end
end

