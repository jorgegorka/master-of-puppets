ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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
