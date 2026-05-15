ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "webmock/minitest"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("test/fixtures/vcr").to_s
  config.hook_into :webmock
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] || "test-anthropic-key" }
  config.default_cassette_options = { record: :new_episodes, match_requests_on: %i[method uri] }
end

# Allow Capybara/Selenium loopback traffic through WebMock
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      Current.session    = sessions(:one) if Session.exists?(sessions(:one).id)
      Current.user       = Current.session&.user
      Current.ip_address = "127.0.0.1"
      Current.user_agent = "test-agent"
    rescue ActiveRecord::Fixture::FixtureError, NoMethodError
      # No sessions fixture available in this test class
    end

    teardown do
      Current.reset
    end
  end
end
