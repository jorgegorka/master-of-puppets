ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "webmock/minitest"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("test/fixtures/vcr").to_s
  config.hook_into :webmock
  config.ignore_localhost = true
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] || "test-anthropic-key" }
  config.default_cassette_options = { record: :new_episodes, match_requests_on: %i[method uri] }
end

# Allow Capybara/Selenium loopback traffic through WebMock.
# Selenium talks to chromedriver on 127.0.0.1 / ::1 which `allow_localhost: true`
# doesn't always cover, so we whitelist the loopback IPs explicitly.
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: %w[127.0.0.1 ::1]
)

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

# Integration tests authenticate over the HTTP boundary by POSTing to the
# sessions controller. Rack::Test's cookie jar can't sign cookies directly, so
# we drive the real sign-in flow — same path the user takes — and inherit the
# signed session cookie from the response.
module ControllerSignInHelpers
  def sign_in_as(user, password: "supersecret123")
    user.update!(password: password)
    post session_path, params: { email: user.email, password: password }
  end
end

class ActionDispatch::IntegrationTest
  include ControllerSignInHelpers
end
