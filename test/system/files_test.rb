require "application_system_test_case"

class FilesSystemTest < ApplicationSystemTestCase
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    File.write(File.join(@tmp, "README.md"), "original readme")
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "admin can edit a workspace file via the browser" do
    admin = User.create!(email: "files-admin@example.test", password: "supersecret123", role: :admin)
    sign_in(admin)

    visit files_path
    click_on "README.md"
    fill_in "Body", with: "rewritten readme"
    click_button "Save"

    assert_text "README.md"
    assert_equal "rewritten readme", File.read(File.join(@tmp, "README.md"))
  end
end
