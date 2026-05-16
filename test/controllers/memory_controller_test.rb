require "test_helper"

class MemoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
    File.write(File.join(@tmp, "memory/MEMORY.md"), "# Memory\n")
    @user = users(:one)
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "signed in shows the memory dashboard" do
    sign_in_as(@user)

    get memory_path
    assert_response :success
    assert_includes response.body, "Memory"
  end

  test "signed out redirects to sign-in" do
    get memory_path
    assert_redirected_to new_session_path
  end
end
