class Settings::Providers::TestsController < ApplicationController
  before_action :require_admin

  def create
    provider = ProviderConfig.find(params[:provider_id])
    Llm::Client.for(provider: provider.provider).ping
    provider.update!(enabled: true) unless provider.enabled?
    redirect_to settings_provider_path(provider), notice: "Connection OK."
  rescue => e
    redirect_to settings_provider_path(params[:provider_id]), alert: "Failed: #{e.message}"
  end
end
