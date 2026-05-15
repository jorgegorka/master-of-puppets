require "test_helper"

class Settings::ProvidersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:one)         # bootstrap admin
    @member   = users(:member)      # non-admin
    @provider = provider_configs(:anthropic)
  end

  test "index lists providers (admin)" do
    sign_in_as(@admin)
    get settings_providers_path
    assert_response :success
    assert_includes response.body, "anthropic"
  end

  test "show renders (admin)" do
    sign_in_as(@admin)
    get settings_provider_path(@provider)
    assert_response :success
  end

  test "update changes attributes (admin)" do
    sign_in_as(@admin)
    patch settings_provider_path(@provider),
      params: { provider_config: { base_url: "https://updated.example.com" } }
    assert_redirected_to settings_provider_path(@provider)
    assert_equal "https://updated.example.com", @provider.reload.base_url
  end

  test "non-admin cannot read providers index" do
    sign_in_as(@member)
    get settings_providers_path
    assert_redirected_to root_path
    assert_match(/admin/i, flash[:alert])
  end

  test "non-admin cannot update a provider" do
    @provider.update!(api_key: "real-secret")
    sign_in_as(@member)
    patch settings_provider_path(@provider),
      params: { provider_config: { api_key: "leaked" } }
    assert_redirected_to root_path
    assert_equal "real-secret", @provider.reload.api_key
  end

  test "blank api_key does not clobber the stored value" do
    sign_in_as(@admin)
    @provider.update!(api_key: "real-secret")
    original = @provider.reload.api_key
    patch settings_provider_path(@provider), params: {
      provider_config: {
        api_key:       "",
        base_url:      "https://example.test",
        default_model: @provider.default_model,
        enabled:       "1"
      }
    }
    assert_equal original, @provider.reload.api_key
    assert_equal "https://example.test", @provider.reload.base_url
  end
end
