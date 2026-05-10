require "test_helper"

class TimelineTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:design_homepage)
  end

  test "entries returns merged sources sorted by created_at descending" do
    timeline = Timeline.new(sources: [ @task.messages, @task.audit_events ])
    entries = timeline.entries

    assert entries.any?
    timestamps = entries.map(&:created_at)
    assert_equal timestamps, timestamps.sort.reverse
  end

  test "entries caps at limit" do
    timeline = Timeline.new(sources: [ @task.messages, @task.audit_events ], limit: 2)
    assert_equal 2, timeline.entries.size
  end

  test "respects before cursor with strict less-than" do
    timeline = Timeline.new(sources: [ @task.audit_events ])
    cursor = timeline.entries.first.created_at

    older = Timeline.new(sources: [ @task.audit_events ], before: cursor).entries
    assert older.all? { |e| e.created_at < cursor }
  end

  test "stable tiebreak by id descending when timestamps tie" do
    now = Time.current
    audits = 3.times.map do |i|
      AuditEvent.create!(auditable: @task, actor: users(:one), action: "tied_#{i}", project: projects(:acme), created_at: now)
    end

    timeline = Timeline.new(sources: [ @task.audit_events.where(action: audits.map(&:action)) ])
    ordered_ids = timeline.entries.map(&:id)
    assert_equal audits.map(&:id).sort.reverse, ordered_ids
  end

  test "more_available? returns true when entries equal limit" do
    timeline = Timeline.new(sources: [ @task.audit_events ], limit: 1)
    assert_equal 1, timeline.entries.size
    assert timeline.more_available?
  end

  test "more_available? returns false when fewer than limit" do
    empty_relation = @task.audit_events.where(action: "nonexistent_action")
    timeline = Timeline.new(sources: [ empty_relation ], limit: 25)
    assert_empty timeline.entries
    assert_not timeline.more_available?
  end

  test "next_cursor returns oldest shown entry's created_at" do
    timeline = Timeline.new(sources: [ @task.audit_events ])
    assert_equal timeline.entries.last.created_at, timeline.next_cursor
  end

  test "empty sources returns empty array" do
    timeline = Timeline.new(sources: [])
    assert_empty timeline.entries
    assert_nil timeline.next_cursor
    assert_not timeline.more_available?
  end

  test "memoizes entries" do
    timeline = Timeline.new(sources: [ @task.audit_events ])
    assert_same timeline.entries, timeline.entries
  end
end
