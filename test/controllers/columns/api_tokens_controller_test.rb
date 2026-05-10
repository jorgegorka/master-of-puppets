require "test_helper"

module Columns
  class ApiTokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
      cookies[:project_id] = projects(:acme).id
    end

    test "rotates token on agent column" do
      column = columns(:acme_in_progress)
      old = column.api_token
      patch column_api_token_url(column)
      assert_redirected_to edit_column_path(column)
      refute_equal old, column.reload.api_token
    end

    test "refuses rotation on manual column" do
      column = columns(:acme_backlog)
      patch column_api_token_url(column)
      assert_redirected_to columns_path
    end
  end
end
