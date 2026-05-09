require "test_helper"

class TaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:acme)
    @other_project = projects(:widgets)
    @user = users(:one)
    @ceo = roles(:ceo)
    @cto = roles(:cto)
    @developer = roles(:developer)
    @task = tasks(:design_homepage)
  end

  # --- Validations ---

  test "valid with title, project, and creator" do
    task = Task.new(title: "New Task", project: @project, creator: @ceo)
    assert task.valid?
  end

  test "invalid without title" do
    task = Task.new(title: nil, project: @project, creator: @ceo)
    assert_not task.valid?
    assert_includes task.errors[:title], "can't be blank"
  end

  test "invalid without creator when project has no roles" do
    empty_project = Project.create!(name: "Empty")
    task = Task.new(title: "Orphan", project: empty_project)
    assert_not task.valid?
    assert_includes task.errors[:creator], "must exist"
  end

  test "destroying role with created tasks is prevented" do
    assert @ceo.created_tasks.exists?
    assert_not @ceo.destroy
    assert_includes @ceo.errors[:base], "Cannot delete record because dependent created tasks exist"
  end

  test "defaults assignee to creator when not specified" do
    task = Task.new(title: "Unassigned", project: @project, creator: @ceo)
    assert task.valid?
    assert_equal @ceo, task.assignee
  end

  test "valid without parent_task (top-level task)" do
    task = Task.new(title: "Top Level", project: @project, creator: @ceo)
    assert task.valid?
    assert_nil task.parent_task
  end

  test "invalid when assignee belongs to different project" do
    other_role = roles(:widgets_lead)
    task = Task.new(title: "Bad Assignee", project: @project, creator: @ceo, assignee: other_role)
    assert_not task.valid?
    assert_includes task.errors[:assignee], "must belong to the same project"
  end

  test "invalid when creator belongs to different project" do
    other_role = roles(:widgets_lead)
    task = Task.new(title: "Bad Creator", project: @project, creator: other_role)
    assert_not task.valid?
    assert_includes task.errors[:creator], "must belong to the same project"
  end

  test "invalid when parent_task belongs to different project" do
    other_task = tasks(:widgets_task)
    task = Task.new(title: "Bad Parent", project: @project, creator: @ceo, parent_task: other_task)
    assert_not task.valid?
    assert_includes task.errors[:parent_task], "must belong to the same project"
  end

  # --- Assignment scope validation ---

  test "valid when assignee is a subordinate of creator" do
    task = Task.new(title: "Delegated", project: @project, creator: @ceo, assignee: @cto)
    assert task.valid?
  end

  test "valid when assignee is a deep subordinate of creator" do
    task = Task.new(title: "Deep delegation", project: @project, creator: @ceo, assignee: @developer)
    assert task.valid?
  end

  test "valid when assignee is a sibling of creator" do
    # developer and process_role are both children of cto
    task = Task.new(title: "Sibling task", project: @project, creator: @developer, assignee: roles(:process_role))
    assert task.valid?
  end

  test "invalid when assignee is not a subordinate or sibling" do
    # developer trying to assign to ceo (parent, not subordinate or sibling)
    task = Task.new(title: "Bad scope", project: @project, creator: @developer, assignee: @ceo)
    assert_not task.valid?
    assert_includes task.errors[:assignee], "must be a subordinate or sibling of the creator role"
  end

  test "valid when creator assigns to self" do
    task = Task.new(title: "Self task", project: @project, creator: @cto, assignee: @cto)
    assert task.valid?
  end

  # --- Enums ---

  test "status enum: open?" do
    task = tasks(:fix_login_bug)
    assert task.open?
  end

  test "status enum: in_progress?" do
    assert @task.in_progress?
  end

  test "status enum: blocked?" do
    task = Task.new(status: :blocked)
    assert task.blocked?
  end

  test "status enum: completed?" do
    assert tasks(:completed_task).completed?
  end

  test "status enum: cancelled?" do
    task = Task.new(status: :cancelled)
    assert task.cancelled?
  end

  test "status enum: pending_review?" do
    task = Task.new(status: :pending_review)
    assert task.pending_review?
  end

  # --- Priority Enums ---

  test "priority enum: low?" do
    assert tasks(:widgets_task).low?
  end

  test "priority enum: medium?" do
    assert tasks(:write_tests).medium?
  end

  test "priority enum: high?" do
    assert @task.high?
  end

  test "priority enum: urgent?" do
    assert tasks(:fix_login_bug).urgent?
  end

  test "invalid status value adds validation error instead of raising" do
    task = tasks(:design_homepage)
    assert_nothing_raised { task.status = "garbage" }
    assert_not task.valid?
    assert_includes task.errors[:status], "is not included in the list"
  end

  test "invalid priority value adds validation error instead of raising" do
    task = tasks(:design_homepage)
    assert_nothing_raised { task.priority = "extreme" }
    assert_not task.valid?
    assert_includes task.errors[:priority], "is not included in the list"
  end

  # --- Associations ---

  test "belongs to project" do
    assert_equal @project, @task.project
  end

  test "belongs to creator (Role)" do
    assert_equal @ceo, @task.creator
  end

  test "belongs to assignee (Role, optional)" do
    assert_equal @cto, @task.assignee
    assert_nil tasks(:write_tests).assignee
  end

  test "belongs to reviewed_by (Role, optional)" do
    assert_nil @task.reviewed_by
  end

  test "belongs to parent_task (Task, optional)" do
    subtask = tasks(:subtask_one)
    assert_equal @task, subtask.parent_task
    assert_nil @task.parent_task
  end

  test "has many subtasks" do
    assert_includes @task.subtasks, tasks(:subtask_one)
  end

  test "has many messages" do
    assert @task.messages.count > 0
  end

  test "has many audit_events via Auditable" do
    assert @task.respond_to?(:audit_events)
    assert @task.respond_to?(:record_audit_event!)
  end

  # --- Scoping ---

  test "for_current_project returns only tasks in Current.project" do
    Current.project = @project
    tasks = Task.for_current_project
    assert_includes tasks, @task
    assert_not_includes tasks, tasks(:widgets_task)
  ensure
    Current.project = nil
  end

  test "active scope excludes completed and cancelled tasks" do
    active = Task.active
    assert_includes active, @task
    assert_not_includes active, tasks(:completed_task)
  end

  test "active scope excludes cancelled tasks" do
    cancelled = Task.create!(title: "Cancelled", project: @project, creator: @ceo, status: :cancelled)
    assert_not_includes Task.active, cancelled
  end

  test "by_priority scope sorts urgent first then by created_at desc" do
    urgent = tasks(:fix_login_bug)  # urgent priority
    high = @task                     # high priority
    Current.project = @project
    ordered = Task.for_current_project.by_priority.to_a
    urgent_index = ordered.index(urgent)
    high_index = ordered.index(high)
    assert_not_nil urgent_index, "urgent task should be in results"
    assert_not_nil high_index, "high priority task should be in results"
    assert urgent_index < high_index, "urgent should come before high priority"
  ensure
    Current.project = nil
  end

  test "roots scope excludes subtasks" do
    roots = Task.roots
    assert_includes roots, @task
    assert_not_includes roots, tasks(:subtask_one)
  end

  test "overdue scope returns active tasks past their due date" do
    overdue = Task.create!(title: "Overdue", project: @project, creator: @ceo, status: :open, due_at: 2.days.ago)
    upcoming = Task.create!(title: "Upcoming", project: @project, creator: @ceo, status: :open, due_at: 2.days.from_now)
    completed_overdue = Task.create!(title: "Done overdue", project: @project, creator: @ceo, status: :completed, due_at: 2.days.ago)
    cancelled_overdue = Task.create!(title: "Cancelled overdue", project: @project, creator: @ceo, status: :cancelled, due_at: 2.days.ago)

    result = Task.overdue
    assert_includes result, overdue
    assert_not_includes result, upcoming
    assert_not_includes result, completed_overdue
    assert_not_includes result, cancelled_overdue
  end

  # --- Callbacks ---

  test "completing a task sets completed_at" do
    task = Task.create!(title: "Fresh Task", project: @project, creator: @ceo, status: :open)
    assert_nil task.completed_at
    task.update!(status: :completed)
    assert_not_nil task.completed_at
  end

  test "reopening a completed task clears completed_at" do
    task = tasks(:completed_task)
    assert_not_nil task.completed_at
    task.update!(status: :open)
    task.reload
    assert_nil task.completed_at
  end

  # --- Pending review wake ---

  test "moving task to pending_review wakes the creator role" do
    task = Task.create!(title: "Review me", project: @project, creator: @cto, assignee: @developer, status: :in_progress)

    assert_difference -> { HeartbeatEvent.count }, 1 do
      task.update!(status: :pending_review)
    end
    event = HeartbeatEvent.last
    assert event.task_pending_review?
    assert_equal @cto, event.role
  end

  # --- Mention wakes ---

  test "creating a task with @Role mention in description wakes that role" do
    assert_difference -> { HeartbeatEvent.where(trigger_type: :mention).count }, 1 do
      Task.create!(
        title: "Investigate auth flow",
        description: "Hey @#{@developer.title}, can you take a look?",
        project: @project,
        creator: @ceo
      )
    end

    event = HeartbeatEvent.where(trigger_type: :mention).last
    assert_equal @developer, event.role
  end

  test "creating a task with @Role in title wakes that role" do
    assert_difference -> { HeartbeatEvent.where(trigger_type: :mention).count }, 1 do
      Task.create!(
        title: "Pair with @#{@developer.title} on rollout",
        project: @project,
        creator: @ceo
      )
    end
  end

  test "task mention wake skips the creator" do
    assert_no_difference -> { HeartbeatEvent.where(trigger_type: :mention).count } do
      Task.create!(
        title: "Self-assigned",
        description: "I (@#{@ceo.title}) will handle this.",
        project: @project,
        creator: @ceo
      )
    end
  end

  test "task without mentions does not fire mention wakes" do
    assert_no_difference -> { HeartbeatEvent.where(trigger_type: :mention).count } do
      Task.create!(title: "Plain task", description: "Nothing fancy.", project: @project, creator: @ceo)
    end
  end

  # --- Audit ---

  test "record_audit_event! creates an AuditEvent linked to the task" do
    assert_difference "AuditEvent.count", 1 do
      @task.record_audit_event!(actor: @user, action: "test_action", metadata: { key: "value" })
    end
    event = AuditEvent.last
    assert_equal @task, event.auditable
    assert_equal @user, event.actor
    assert_equal "test_action", event.action
  end

  # --- Deletion ---

  test "destroying task destroys its messages" do
    task = tasks(:design_homepage)
    msg_count = task.messages.count
    assert msg_count > 0
    assert_difference "Message.count", -msg_count do
      task.destroy
    end
  end

  test "destroying task destroys its subtasks" do
    subtask_count = @task.subtasks.count
    assert subtask_count > 0
    assert_difference "Task.count", -(subtask_count + 1) do
      @task.destroy
    end
  end

  test "destroying task destroys its audit_events and records destroy event on project" do
    @task.record_audit_event!(actor: @user, action: "test")
    task_event_count = @task.audit_events.count
    assert task_event_count > 0

    subtask_count = @task.subtasks.count
    @task.destroy

    # Task's own audit events should be gone
    assert_equal 0, AuditEvent.where(auditable: @task).count

    # Destroy events recorded on the project for the task and its subtasks
    destroy_events = AuditEvent.where(action: "destroyed", auditable: @project).order(:id).last(subtask_count + 1)
    task_destroy = destroy_events.find { |e| e.metadata["destroyed_id"] == @task.id && e.metadata["destroyed_type"] == "Task" }
    assert task_destroy, "Expected a destroy audit event for the task"
    assert_equal @task.title, task_destroy.metadata["title"]
  end

  test "destroying project destroys its tasks" do
    task_count = @project.tasks.count
    assert task_count > 0
    assert_difference "Task.count", -task_count do
      @project.destroy
    end
  end

  test "destroying role nullifies assignee_id" do
    task = tasks(:design_homepage)
    assert_not_nil task.assignee_id
    cto = roles(:cto)
    cto.created_tasks.update_all(creator_id: @ceo.id)
    cto.destroy
    task.reload
    assert_nil task.assignee_id
  end

  # --- Cost ---

  test "valid with cost_cents" do
    task = tasks(:design_homepage)
    task.cost_cents = 5000
    assert task.valid?
  end

  test "valid with nil cost_cents" do
    task = tasks(:write_tests)
    task.cost_cents = nil
    assert task.valid?
  end

  test "invalid with negative cost_cents" do
    task = tasks(:design_homepage)
    task.cost_cents = -100
    assert_not task.valid?
    assert_includes task.errors[:cost_cents], "must be greater than or equal to 0"
  end

  test "valid with zero cost_cents" do
    task = tasks(:design_homepage)
    task.cost_cents = 0
    assert task.valid?
  end

  test "cost_in_dollars returns dollar amount" do
    task = tasks(:design_homepage)
    task.cost_cents = 1500
    assert_equal 15.0, task.cost_in_dollars
  end

  test "cost_in_dollars returns nil when cost_cents is nil" do
    task = tasks(:write_tests)
    task.cost_cents = nil
    assert_nil task.cost_in_dollars
  end

  # --- Real-time broadcasts ---

  test "task status change does not error" do
    assert_nothing_raised do
      @task.update!(status: :completed)
    end
  end

  # --- Task alignment evaluation trigger ---

  test "enqueues task alignment evaluation job when subtask completes with non-agent creator" do
    root = Task.create!(title: "Mission", project: @project, creator: @ceo, assignee: @cto, status: :open)
    task = Task.create!(title: "Eval trigger test", project: @project, creator: @ceo, assignee: @cto, parent_task: root, status: :open)

    assert_enqueued_with(job: EvaluateTaskAlignmentJob) do
      task.update!(status: :completed)
    end
  end

  test "does not enqueue task alignment evaluation when creator is an agent-configured role" do
    root = Task.create!(title: "Mission", project: @project, creator: @ceo, assignee: @cto, status: :open)
    task = Task.create!(title: "Agent eval test", project: @project, creator: @cto, assignee: @developer, parent_task: root, status: :open)

    assert_no_enqueued_jobs(only: EvaluateTaskAlignmentJob) do
      task.update!(status: :completed)
    end
  end

  test "does not enqueue task alignment evaluation when task has no parent (root task)" do
    task = Task.create!(title: "Root task", project: @project, creator: @ceo, assignee: @cto, status: :open)

    assert_no_enqueued_jobs(only: EvaluateTaskAlignmentJob) do
      task.update!(status: :completed)
    end
  end

  test "does not enqueue task alignment evaluation when task is not completed" do
    root = Task.create!(title: "Mission", project: @project, creator: @ceo, assignee: @cto, status: :open)
    task = Task.create!(title: "Not completed test", project: @project, creator: @ceo, assignee: @cto, parent_task: root, status: :open)

    assert_no_enqueued_jobs(only: EvaluateTaskAlignmentJob) do
      task.update!(status: :in_progress)
    end
  end

  # --- Completion percentage ---

  test "recalculate_completion! computes from subtasks" do
    parent = Task.create!(title: "Parent", project: @project, creator: @ceo, status: :open)
    Task.create!(title: "Sub 1", project: @project, creator: @ceo, parent_task: parent, status: :completed)
    Task.create!(title: "Sub 2", project: @project, creator: @ceo, parent_task: parent, status: :open)

    parent.recalculate_completion!
    assert_equal 50, parent.completion_percentage
  end

  test "recalculate_completion! returns 0 when no subtasks" do
    parent = Task.create!(title: "No subs", project: @project, creator: @ceo, status: :open)
    parent.recalculate_completion!
    assert_equal 0, parent.completion_percentage
  end

  test "recalculate_completion! returns 100 when all subtasks completed" do
    parent = Task.create!(title: "All done", project: @project, creator: @ceo, status: :open)
    Task.create!(title: "Sub 1", project: @project, creator: @ceo, parent_task: parent, status: :completed)
    Task.create!(title: "Sub 2", project: @project, creator: @ceo, parent_task: parent, status: :completed)

    parent.recalculate_completion!
    assert_equal 100, parent.completion_percentage
  end

  # --- Auto-transition on subtask completion ---

  test "auto-transitions in_progress task to pending_review when all subtasks completed and has parent" do
    grandparent = Task.create!(title: "GP", project: @project, creator: @ceo, status: :in_progress)
    parent = Task.create!(title: "Parent", project: @project, creator: @ceo, parent_task: grandparent, assignee: @cto, status: :in_progress)
    Task.create!(title: "Sub 1", project: @project, creator: @cto, parent_task: parent, status: :completed)
    Task.create!(title: "Sub 2", project: @project, creator: @cto, parent_task: parent, status: :completed)

    parent.recalculate_completion!

    assert_equal 100, parent.completion_percentage
    assert_equal "pending_review", parent.reload.status
  end

  test "auto-transitions in_progress root task to completed when all subtasks completed" do
    parent = Task.create!(title: "Root", project: @project, creator: @ceo, assignee: @cto, status: :in_progress)
    Task.create!(title: "Sub 1", project: @project, creator: @cto, parent_task: parent, status: :completed)

    parent.recalculate_completion!

    assert_equal 100, parent.completion_percentage
    assert_equal "completed", parent.reload.status
    assert_not_nil parent.completed_at
  end

  test "does not auto-transition when not all subtasks completed" do
    parent = Task.create!(title: "Partial", project: @project, creator: @ceo, assignee: @cto, status: :in_progress)
    Task.create!(title: "Done", project: @project, creator: @cto, parent_task: parent, status: :completed)
    Task.create!(title: "Open", project: @project, creator: @cto, parent_task: parent, status: :open)

    parent.recalculate_completion!

    assert_equal 50, parent.completion_percentage
    assert_equal "in_progress", parent.reload.status
  end

  test "does not auto-transition task already in pending_review" do
    parent = Task.create!(title: "Already PR", project: @project, creator: @ceo, assignee: @cto, parent_task: @task, status: :pending_review)
    Task.create!(title: "Sub", project: @project, creator: @cto, parent_task: parent, status: :completed)

    parent.recalculate_completion!

    assert_equal "pending_review", parent.reload.status
  end

  test "does not auto-transition task already completed" do
    parent = Task.create!(title: "Already done", project: @project, creator: @ceo, assignee: @cto, status: :completed)
    Task.create!(title: "Sub", project: @project, creator: @cto, parent_task: parent, status: :completed)

    parent.recalculate_completion!

    assert_equal "completed", parent.reload.status
  end

  test "does not auto-transition task with no subtasks" do
    task = Task.create!(title: "No subs", project: @project, creator: @ceo, assignee: @cto, status: :in_progress)

    task.recalculate_completion!

    assert_equal "in_progress", task.reload.status
  end

  test "completing subtask enqueues RecalculateTaskCompletionJob for parent" do
    parent = Task.create!(title: "Parent", project: @project, creator: @ceo, status: :open)
    sub = Task.create!(title: "Sub", project: @project, creator: @ceo, parent_task: parent, status: :open)

    assert_enqueued_with(job: RecalculateTaskCompletionJob, args: [ parent.id ]) do
      sub.update!(status: :completed)
    end
  end

  # --- Leaf task completion percentage sync ---

  test "leaf task sets completion_percentage to 100 when completed" do
    task = Task.create!(title: "Leaf", project: @project, creator: @ceo, assignee: @cto, status: :pending_review)
    task.approve_by!(@ceo)

    assert_equal 100, task.reload.completion_percentage
  end

  test "leaf task resets completion_percentage to 0 when rejected back to open" do
    task = Task.create!(title: "Leaf", project: @project, creator: @ceo, assignee: @cto, status: :pending_review)
    task.approve_by!(@ceo)
    assert_equal 100, task.reload.completion_percentage

    # Simulate reopening (e.g. status reset)
    task.update!(status: :open)
    assert_equal 0, task.reload.completion_percentage
  end

  test "sync_leaf_completion_percentage does not affect tasks with subtasks" do
    parent = Task.create!(title: "Parent", project: @project, creator: @ceo, assignee: @cto, status: :in_progress)
    Task.create!(title: "Sub", project: @project, creator: @cto, parent_task: parent, status: :open)

    parent.update!(status: :completed)
    assert_equal 0, parent.reload.completion_percentage
  end
end
