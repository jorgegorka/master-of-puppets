require "test_helper"

class BoardRoutesTest < ActionDispatch::IntegrationTest
  test "columns index/new/create routes" do
    assert_routing({ method: :get,  path: "/columns" },     controller: "columns", action: "index")
    assert_routing({ method: :get,  path: "/columns/new" }, controller: "columns", action: "new")
    assert_routing({ method: :post, path: "/columns" },     controller: "columns", action: "create")
  end

  test "columns member routes" do
    assert_routing({ method: :get,    path: "/columns/1" },      controller: "columns", action: "show", id: "1")
    assert_routing({ method: :get,    path: "/columns/1/edit" }, controller: "columns", action: "edit", id: "1")
    assert_routing({ method: :patch,  path: "/columns/1" },      controller: "columns", action: "update", id: "1")
    assert_routing({ method: :delete, path: "/columns/1" },      controller: "columns", action: "destroy", id: "1")
  end

  test "column activity is a singular nested resource (start/stop = create/destroy)" do
    assert_routing({ method: :post,   path: "/columns/1/activity" }, controller: "columns/activities", action: "create",  column_id: "1")
    assert_routing({ method: :delete, path: "/columns/1/activity" }, controller: "columns/activities", action: "destroy", column_id: "1")
  end

  test "column runs are nested resources" do
    assert_routing({ method: :get, path: "/columns/1/runs" },   controller: "columns/runs", action: "index", column_id: "1")
    assert_routing({ method: :get, path: "/columns/1/runs/2" }, controller: "columns/runs", action: "show",  column_id: "1", id: "2")
  end

  test "column api_token rotation is a singular nested resource" do
    assert_routing({ method: :patch, path: "/columns/1/api_token" }, controller: "columns/api_tokens", action: "update", column_id: "1")
  end

  test "run show + cancellation" do
    assert_routing({ method: :get,  path: "/runs/1" },              controller: "runs",               action: "show",   id: "1")
    assert_routing({ method: :post, path: "/runs/1/cancellation" }, controller: "runs/cancellations", action: "create", run_id: "1")
  end

  test "task transitions/approval/rejection use RESTful CRUD" do
    assert_routing({ method: :post,  path: "/tasks/1/transition" }, controller: "tasks/transitions", action: "create", task_id: "1")
    assert_routing({ method: :patch, path: "/tasks/1/approval" },   controller: "tasks/approvals",   action: "update", task_id: "1")
    assert_routing({ method: :patch, path: "/tasks/1/rejection" },  controller: "tasks/rejections",  action: "update", task_id: "1")
  end

  test "deleted routes return ActionController::RoutingError" do
    deleted = [
      [ :get,    "/roles" ],
      [ :get,    "/roles/new" ],
      [ :get,    "/roles/1" ],
      [ :get,    "/roles.json" ],
      [ :get,    "/agents" ],
      [ :get,    "/agents/1" ],
      [ :get,    "/agent_runs" ],
      [ :get,    "/role_runs" ],
      [ :get,    "/org_chart" ],
      [ :get,    "/role_templates" ],
      [ :get,    "/approval_gates" ],
      [ :post,   "/roles/1/start" ],
      [ :delete, "/roles/1/stop" ]
    ]

    deleted.each do |method, path|
      assert_raises(ActionController::RoutingError, "expected #{method.upcase} #{path} to 404") do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
  end
end
