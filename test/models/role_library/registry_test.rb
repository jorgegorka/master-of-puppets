require "test_helper"

class RoleLibrary::RegistryTest < ActiveSupport::TestCase
  teardown do
    RoleLibrary::Registry.reset!
  end

  # --- .all ---

  test "all returns all library roles" do
    roles = RoleLibrary::Registry.all
    assert roles.size >= 8, "expected at least 8 library roles, got #{roles.size}"
  end

  test "all returns frozen array" do
    assert RoleLibrary::Registry.all.frozen?
  end

  test "all caches results across calls" do
    first = RoleLibrary::Registry.all
    second = RoleLibrary::Registry.all
    assert_same first, second
  end

  # --- .find ---

  test "find returns role by key" do
    role = RoleLibrary::Registry.find("cto")
    assert_equal "cto", role.key
    assert_equal "CTO", role.title
  end

  test "find accepts symbol key" do
    role = RoleLibrary::Registry.find(:cto)
    assert_equal "cto", role.key
  end

  test "find raises RoleNotFound for unknown key" do
    error = assert_raises(RoleLibrary::Registry::RoleNotFound) do
      RoleLibrary::Registry.find("nonexistent_role")
    end
    assert_match(/nonexistent_role/, error.message)
  end

  # --- .keys / .exists? ---

  test "keys returns all library role keys" do
    keys = RoleLibrary::Registry.keys
    assert_includes keys, "cto"
    assert_includes keys, "developer"
  end

  test "exists? returns true for a known key" do
    assert RoleLibrary::Registry.exists?("cto")
  end

  test "exists? returns false for an unknown key" do
    assert_not RoleLibrary::Registry.exists?("nonexistent_role")
  end

  # --- LibraryRole shape ---

  test "library role exposes required attributes" do
    role = RoleLibrary::Registry.find("cto")
    assert_kind_of String, role.key
    assert_kind_of String, role.title
    assert_kind_of String, role.description
    assert_kind_of String, role.category
    assert_kind_of String, role.job_spec
    assert_kind_of Array,  role.skill_keys
  end

  test "library role category is one of the known values" do
    valid = %w[Orchestrator Executor]
    RoleLibrary::Registry.all.each do |role|
      assert_includes valid, role.category,
        "#{role.key} has invalid category '#{role.category}'"
    end
  end

  test "library role has non-blank title description and job_spec" do
    RoleLibrary::Registry.all.each do |role|
      assert role.title.present?,       "#{role.key} has blank title"
      assert role.description.present?, "#{role.key} has blank description"
      assert role.job_spec.present?,    "#{role.key} has blank job_spec"
    end
  end

  test "library role skill_keys is frozen" do
    role = RoleLibrary::Registry.find("cto")
    assert role.skill_keys.frozen?
  end

  # --- reset! ---

  test "reset! clears cached roles" do
    first = RoleLibrary::Registry.all
    RoleLibrary::Registry.reset!
    second = RoleLibrary::Registry.all
    refute_same first, second
  end
end
