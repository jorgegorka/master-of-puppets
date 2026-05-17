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

  # Asserts that GETting `path` as the currently signed-in user returns 404.
  # Used by Phase 6+ controller tests where the setup already creates a
  # resource owned by a foreign tenant and signs in as the local user — the
  # scoped `before_action` (`Current.user.swarm_missions.find(...)`) raises
  # ActiveRecord::RecordNotFound, which the test env renders as 404.
  def assert_404_for_cross_tenant_show(path)
    get path
    assert_response :not_found
  end
end
