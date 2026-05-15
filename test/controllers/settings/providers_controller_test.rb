require "test_helper"

class Settings::ProvidersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "supersecret123")
    post session_path, params: { email: @user.email, password: "supersecret123" }
  end

  test "index lists providers" do
    get settings_providers_path
    assert_response :success
    assert_includes response.body, "anthropic"
  end

  test "show renders" do
    get settings_provider_path(provider_configs(:anthropic))
    assert_response :success
  end

  test "update changes attributes" do
    patch settings_provider_path(provider_configs(:anthropic)),
      params: { provider_config: { base_url: "https://updated.example.com" } }
    assert_redirected_to settings_provider_path(provider_configs(:anthropic))
    assert_equal "https://updated.example.com", provider_configs(:anthropic).reload.base_url
  end
end
