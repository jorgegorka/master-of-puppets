require "test_helper"
require_relative "concerns/cross_tenancy_assertions"

class ChatSessionsCrossTenancyTest < ActionDispatch::IntegrationTest
  include CrossTenancyAssertions

  test "cannot show another user's chat session" do
    assert_cross_tenant_denied { |cs| get chat_session_path(cs) }
  end

  test "cannot post a message into another user's chat session" do
    assert_cross_tenant_denied { |cs| post chat_session_messages_path(cs), params: { content: "hi" } }
  end

  test "cannot fork another user's chat session" do
    assert_cross_tenant_denied do |cs|
      foreign_message = cs.messages.create!(
        role:           :user,
        content_blocks: [ { type: "text", text: "x" } ],
        status:         :completed,
        model:          cs.model,
        provider:       cs.provider
      )
      post chat_session_forks_path(cs), params: { message_id: foreign_message.id }
    end
  end

  test "cannot archive another user's chat session" do
    assert_cross_tenant_denied { |cs| post chat_session_archive_path(cs) }
  end

  test "cannot pin another user's chat session" do
    assert_cross_tenant_denied { |cs| post chat_session_pin_path(cs) }
  end
end
