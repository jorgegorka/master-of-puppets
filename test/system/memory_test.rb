require "application_system_test_case"

class MemorySystemTest < ApplicationSystemTestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
    File.write(File.join(@tmp, "memory/note.md"), "# Original title\n\nfirst draft")
    MemoryFile.reindex("note.md")
  end

  teardown do
    MemoryFileFts.connection.execute("DELETE FROM memory_files_fts")
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "edit a memory file in the browser and find it via search" do
    user = User.create!(email: "memory@example.test", password: "supersecret123")
    sign_in(user)

    visit memory_path
    assert_text "Original title"

    click_on "Original title"
    fill_in "Body", with: "# Updated title\n\nrewritten body about dragons"
    click_button "Save"

    assert_text "Updated title"
    assert_equal "# Updated title\n\nrewritten body about dragons",
                 File.read(File.join(@tmp, "memory/note.md"))

    visit memory_path
    fill_in "Search memory…", with: "dragons"
    click_button "Search"
    assert_text "note.md"
  end
end
