require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "user signs in" do
    User.create!(email: "a@b.com", password: "supersecret123")
    visit new_session_path
    fill_in "Email", with: "a@b.com"
    fill_in "Password", with: "supersecret123"
    click_button "Sign in"
    assert_text "Dashboard"
  end

  test "user signs in with wrong password" do
    User.create!(email: "a@b.com", password: "supersecret123")
    visit new_session_path
    fill_in "Email", with: "a@b.com"
    fill_in "Password", with: "WRONG"
    click_button "Sign in"
    assert_text "Invalid email or password"
  end
end
