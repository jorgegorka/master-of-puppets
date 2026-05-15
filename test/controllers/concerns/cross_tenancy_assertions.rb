module CrossTenancyAssertions
  extend ActiveSupport::Concern

  # Signs the calling test in as users(:one) and yields a chat_session that
  # belongs to users(:member). ChatSessionScoped#set_chat_session looks up the
  # row through Current.user.chat_sessions, so a foreign row raises
  # ActiveRecord::RecordNotFound — the test env's show_exceptions: :rescuable
  # turns that into a 404 at the HTTP boundary.
  def assert_cross_tenant_denied(&request)
    other   = users(:member)
    foreign = other.chat_sessions.create!(
      title:    "theirs",
      model:    "claude-opus-4-7",
      provider: "anthropic"
    )
    sign_in_as(users(:one))
    yield(foreign)
    assert_response :not_found
  end
end
