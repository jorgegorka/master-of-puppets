require "application_system_test_case"

class ChatSessionSystemTest < ApplicationSystemTestCase
  test "user creates a chat session and the show page renders" do
    user = User.create!(email: "chat@example.test", password: "supersecret123")
    sign_in(user)
    visit chat_sessions_path
    click_on "+ New chat"
    fill_in "Title", with: "My first chat"
    click_button "Create"
    assert_text "My first chat"
    assert_selector "textarea"
    assert_selector "input[type=submit][value=Send]"
  end
end
