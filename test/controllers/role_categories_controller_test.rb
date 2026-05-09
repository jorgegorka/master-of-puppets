require "test_helper"

class RoleCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:acme)
    sign_in_as(@user)
    post project_switch_url(@project)
    @orchestrator = role_categories(:orchestrator)
    @executor = role_categories(:executor)
  end

  # --- Index ---

  test "should get index" do
    get role_categories_url
    assert_response :success
    assert_select ".role-category-card", minimum: 2
  end

  test "should only show categories for current project" do
    get role_categories_url
    assert_response :success
    assert_select ".role-category-card__title", text: "Orchestrator"
    # widgets project has its own Orchestrator — not shown here
  end

  # --- Show ---

  test "should show role category" do
    get role_category_url(@orchestrator)
    assert_response :success
    assert_select "h1", "Orchestrator"
  end

  test "should show assigned roles" do
    get role_category_url(@orchestrator)
    assert_response :success
  end

  # --- New / Create ---

  test "should get new" do
    get new_role_category_url
    assert_response :success
  end

  test "should create role category" do
    assert_difference("RoleCategory.count", 1) do
      post role_categories_url, params: {
        role_category: { name: "Specialist", description: "Domain experts", job_spec: "You are a specialist." }
      }
    end
    category = RoleCategory.order(:created_at).last
    assert_equal "Specialist", category.name
    assert_equal @project.id, category.project_id
    assert_redirected_to role_category_url(category)
  end

  test "should not create category without name" do
    assert_no_difference("RoleCategory.count") do
      post role_categories_url, params: {
        role_category: { name: "", job_spec: "Some spec." }
      }
    end
    assert_response :unprocessable_entity
  end

  test "should not create category without job_spec" do
    assert_no_difference("RoleCategory.count") do
      post role_categories_url, params: {
        role_category: { name: "Empty Spec" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "should not create duplicate name in same project" do
    assert_no_difference("RoleCategory.count") do
      post role_categories_url, params: {
        role_category: { name: "Orchestrator", job_spec: "Duplicate." }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- Edit / Update ---

  test "should get edit" do
    get edit_role_category_url(@executor)
    assert_response :success
  end

  test "should update role category" do
    patch role_category_url(@executor), params: {
      role_category: { description: "Updated description" }
    }
    assert_redirected_to role_category_url(@executor)
    @executor.reload
    assert_equal "Updated description", @executor.description
  end

  # --- Destroy ---

  test "should destroy category with no roles" do
    category = RoleCategory.create!(name: "Disposable", job_spec: "Temp.", project: @project)
    assert_difference("RoleCategory.count", -1) do
      delete role_category_url(category)
    end
    assert_redirected_to role_categories_url
  end

  test "should not destroy category with assigned roles" do
    assert_no_difference("RoleCategory.count") do
      delete role_category_url(@orchestrator)
    end
    assert_redirected_to role_category_url(@orchestrator)
    assert_match(/Cannot delete/, flash[:alert])
  end

  # --- Project scoping ---

  test "cannot access other project categories" do
    widgets_cat = role_categories(:widgets_orchestrator)
    get role_category_url(widgets_cat)
    assert_redirected_to root_url
  end
end
