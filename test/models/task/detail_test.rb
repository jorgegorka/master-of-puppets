require "test_helper"

class Task::DetailTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:design_homepage)
    @detail = Task::Detail.new(@task)
  end

  test "exposes the task" do
    assert_equal @task, @detail.task
  end

  test "messages returns root messages in chronological order" do
    messages = @detail.messages
    assert messages.all? { |m| m.parent_id.nil? }
    assert_equal messages.sort_by(&:created_at), messages.to_a
  end

  test "messages eager loads authors and replies" do
    @detail.messages.each do |message|
      assert message.association(:author).loaded?
      assert message.association(:replies).loaded?
    end
  end

  test "messages is memoized" do
    assert_same @detail.messages, @detail.messages
  end

  test "document_links returns task documents ordered by document title" do
    links = @detail.document_links
    assert links.any?
    titles = links.map { |td| td.document.title }
    assert_equal titles.sort, titles
  end

  test "document_links eager loads documents" do
    @detail.document_links.each do |td|
      assert td.association(:document).loaded?
    end
  end

  test "document_links is memoized" do
    assert_same @detail.document_links, @detail.document_links
  end

  test "any_documents? returns true when documents exist" do
    assert @detail.any_documents?
  end

  test "any_documents? returns false when no documents" do
    detail = Task::Detail.new(tasks(:fix_login_bug))
    assert_not detail.any_documents?
  end

  test "timeline_entries returns a Timeline" do
    assert_kind_of Timeline, @detail.timeline_entries
  end

  test "timeline_entries merges messages, audit_events, and task_evaluations" do
    detail = Task::Detail.new(tasks(:eval_ready_task))
    types = detail.timeline_entries.entries.map(&:class).map(&:name).uniq
    assert_includes types, "TaskEvaluation"
  end

  test "timeline_entries respects the before cursor" do
    timeline = @detail.timeline_entries
    cursor = timeline.entries.first.created_at
    older = @detail.timeline_entries(before: cursor).entries
    assert older.all? { |e| e.created_at < cursor }
  end
end
