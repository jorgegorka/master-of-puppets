class Settings::ProvidersController < ApplicationController
  before_action :set_provider, only: %i[show update]

  def index
    @providers = ProviderConfig.order(:provider)
  end

  def show
  end

  def update
    @provider.update!(provider_params)
    redirect_to settings_provider_path(@provider), notice: "Saved."
  end

  private
    def set_provider
      @provider = ProviderConfig.find(params[:id])
    end

    def provider_params
      params.expect(provider_config: %i[api_key base_url default_model enabled])
    end
end
