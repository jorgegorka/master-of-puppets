class Settings::ProvidersController < ApplicationController
  before_action :require_admin
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

    # Strip a blank :api_key so "leave blank to keep current" doesn't clobber
    # the encrypted value with "" when the form is resubmitted without
    # retyping the key.
    def provider_params
      attrs = params.expect(provider_config: %i[api_key base_url default_model enabled])
      attrs.delete(:api_key) if attrs[:api_key].blank?
      attrs
    end
end
