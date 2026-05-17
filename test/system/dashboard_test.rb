require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "dashboard updates when a JobRun finishes" do
    sign_in(users(:one))
    visit root_path
    assert_text "Dashboard"
    job_runs(:succeeded_one).update!(status: :failed)
    using_wait_time(3) { assert_text "failed" }
  end
end
