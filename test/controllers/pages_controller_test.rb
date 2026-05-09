require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated visitors see the homepage at root" do
    get root_url
    assert_response :success
    assert_select "title", /Master of Puppets/
    assert_select "h1.home-hero__headline"
    assert_select "a[href='#{new_session_path}']"
    assert_select "a[href='#{new_registration_path}']"
  end

  test "authenticated users are redirected to the dashboard" do
    sign_in_as(users(:one))
    get root_url
    assert_redirected_to dashboard_url
  end
end
