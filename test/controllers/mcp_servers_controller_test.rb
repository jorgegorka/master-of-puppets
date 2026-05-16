require "test_helper"

class McpServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))  # admin
  end

  test "index lists user's MCP servers" do
    get mcp_servers_path
    assert_response :success
    assert_select "h1", "MCP servers"
  end

  test "new renders the form" do
    get new_mcp_server_path
    assert_response :success
    assert_select "form"
  end

  test "create persists a new server" do
    assert_difference -> { Current.user.mcp_servers.count }, +1 do
      post mcp_servers_path, params: { mcp_server: {
        slug: "newone", name: "New MCP", transport_type: :http, url: "https://example.com", auth_type: :none
      } }
    end
    assert_redirected_to mcp_server_path(Current.user.mcp_servers.order(:created_at).last)
  end

  test "create with missing url for http transport renders new" do
    assert_no_difference -> { Current.user.mcp_servers.count } do
      post mcp_servers_path, params: { mcp_server: { slug: "no-url", name: "x", transport_type: :http } }
    end
    assert_response :unprocessable_content
  end

  test "show renders the server detail" do
    get mcp_server_path(mcp_servers(:context7_http))
    assert_response :success
  end

  test "destroy removes the server" do
    server = users(:one).mcp_servers.create!(slug: "kill", name: "k", transport_type: :http, url: "https://example.com")
    assert_difference -> { Current.user.mcp_servers.count }, -1 do
      delete mcp_server_path(server)
    end
    assert_redirected_to mcp_servers_path
  end

  test "non-admin users are redirected" do
    delete session_path # sign out admin
    sign_in_as(users(:member))
    get mcp_servers_path
    assert_redirected_to root_path
  end

  test "cross-tenancy: another user cannot access a server" do
    # Sign in as member instead. mcp_servers fixtures belong to users(:one).
    delete session_path
    member = users(:member)
    member.update!(role: :admin)
    sign_in_as(member)
    get mcp_server_path(mcp_servers(:context7_http))
    assert_response :not_found
  end
end
