require "test_helper"

class SwarmMissionTest < ActiveSupport::TestCase
  setup { Current.user = users(:one) }

  test "validates title + goal presence" do
    m = SwarmMission.new
    assert_not m.valid?
    assert_includes m.errors[:title], "can't be blank"
    assert_includes m.errors[:goal],  "can't be blank"
  end

  test "state enum default is :planning and mode default is :auto" do
    m = SwarmMission.create!(title: "X", goal: "Y")
    assert_equal "planning", m.state
    assert_equal "auto",     m.mode
    assert_predicate m, :planning?
    assert_predicate m, :auto?
  end

  test "active scope excludes :complete and :cancelled" do
    complete  = SwarmMission.create!(title: "C", goal: "G", state: :complete)
    cancelled = SwarmMission.create!(title: "X", goal: "G", state: :cancelled)
    executing = SwarmMission.create!(title: "E", goal: "G", state: :executing)
    assert_includes SwarmMission.active,    executing
    refute_includes SwarmMission.active,    complete
    refute_includes SwarmMission.active,    cancelled
  end

  test "default belongs_to :user resolves from Current.user" do
    m = SwarmMission.create!(title: "X", goal: "Y")
    assert_equal users(:one), m.user
    assert_equal users(:one), m.created_by
  end
end
