require "test_helper"

class ProviderConfigTest < ActiveSupport::TestCase
  test "api_key encrypts at rest" do
    ProviderConfig.create!(provider: "test-x", base_url: "https://x", api_key: "shh-shh-shh", default_model: "m", enabled: true)
    raw = ActiveRecord::Base.connection.execute("SELECT api_key FROM provider_configs WHERE provider='test-x'").first
    refute_includes raw.fetch("api_key").to_s, "shh-shh-shh"
  end

  test "enabled scope filters out disabled" do
    enabled_count = ProviderConfig.enabled.count
    assert_equal 1, enabled_count, "fixtures should have one enabled provider"
  end

  test "provider uniqueness validated" do
    dup = ProviderConfig.new(provider: "anthropic", base_url: "https://x", default_model: "m")
    refute dup.valid?
    assert_includes dup.errors[:provider], "has already been taken"
  end
end
