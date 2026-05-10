require "test_helper"

module Columns
  class ActivitiesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @user = users(:one)
      sign_in_as(@user)
      cookies[:project_id] = projects(:acme).id
    end

    test "create refused on manual column" do
      column = columns(:acme_backlog)
      post column_activity_url(column)
      assert_redirected_to columns_path
    end

    test "create refused when column has no eligible tasks" do
      column = columns(:acme_in_progress)
      column.tasks.update_all(column_id: columns(:acme_backlog).id)
      post column_activity_url(column)
      assert_redirected_to columns_path
    end

    test "destroy cancels active runs" do
      column = columns(:acme_in_progress)
      delete column_activity_url(column)
      assert_redirected_to columns_path
    end
  end
end
