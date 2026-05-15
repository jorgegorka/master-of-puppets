require "test_helper"
require "capybara/rails"
require "capybara/minitest"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  def sign_in(user, password: "supersecret123")
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Sign in"
  end
end
