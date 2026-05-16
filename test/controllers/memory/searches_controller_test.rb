require "test_helper"

class Memory::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp       = Dir.mktmpdir
    @prev_home = Rails.application.config.x.mop_home
    Rails.application.config.x.mop_home = @tmp
    FileUtils.mkdir_p(File.join(@tmp, "memory"))
    @user   = users(:one)
    @member = users(:member)
    sign_in_as(@user)
  end

  teardown do
    MemoryFileFts.connection.execute("DELETE FROM memory_files_fts")
    FileUtils.rm_rf(@tmp)
    Rails.application.config.x.mop_home = @prev_home
  end

  test "create renders matching files for the query" do
    File.write(File.join(@tmp, "memory/dragon.md"), "# Dragon\n\nthe dragon roars")
    File.write(File.join(@tmp, "memory/quiet.md"),  "# Quiet\n\nshhh")
    MemoryFile.reindex_all

    post memory_searches_path, params: { query: "dragon" }

    assert_response :success
    assert_includes response.body, "dragon.md"
    refute_includes response.body, "quiet.md"
  end

  test "create with a blank query renders an empty results page" do
    post memory_searches_path, params: { query: "" }

    assert_response :success
    assert_match(/no matches/i, response.body)
  end

  test "non-admin cannot search" do
    sign_in_as(@member)
    post memory_searches_path, params: { query: "dragon" }
    assert_redirected_to root_path
  end
end
