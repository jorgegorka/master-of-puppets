require "test_helper"

class FilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    File.write(File.join(@tmp, "README.md"), "# Hello\n")
    @admin  = users(:one)
    @member = users(:member)
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "admin can browse the workspace" do
    sign_in_as(@admin)
    get files_path
    assert_response :success
    assert_includes response.body, "Files"
    assert_includes response.body, "README.md"
  end

  test "non-admin is redirected" do
    sign_in_as(@member)
    get files_path
    assert_redirected_to root_path
  end

  test "signed-out is redirected to sign-in" do
    get files_path
    assert_redirected_to new_session_path
  end
end
