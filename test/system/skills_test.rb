require "application_system_test_case"

class SkillsTest < ApplicationSystemTestCase
  setup do
    @user  = users(:one)
    @skill = skills(:filesystem)
  end

  test "user installs and enables a skill via the UI" do
    sign_in(@user)

    visit skills_path
    # Trip the assertion if the badge CSS is ever removed — the helper
    # emits `.badge.badge--<variant>` and the system test needs the
    # styles to actually exist for the page to render correctly.
    assert_selector ".badge.badge--ok, .badge.badge--warn, .badge.badge--danger"
    click_link @skill.name
    click_button "Install"
    assert_text "Installed."
    click_button "Enable"
    assert_text "Enabled."
  end

  test "a skill name change appears in /skills without reload" do
    sign_in(@user)
    visit skills_path
    assert_text @skill.name

    @skill.update!(name: "Filesystem Updated")
    using_wait_time(3) { assert_text "Filesystem Updated" }
  end

  test "typing a 2-char prefix narrows the skill list" do
    # Seed an FTS row for the fixture skill so the autocomplete query
    # (Skill.matching("fi")) actually hits a row. The standard fixture
    # load path doesn't trigger Skill::Loadable#flush_fts_write.
    @skill.reindex_fts_entry!(slug: @skill.slug, name: @skill.name,
                              category: @skill.category,
                              description: @skill.description.to_s, body: "")

    sign_in(@user)
    visit skills_path
    within("turbo-frame#skill-results") { assert_text @skill.name }
    fill_in "skills_q", with: "fi"
    within("turbo-frame#skill-results") { assert_text @skill.name }
  end
end
