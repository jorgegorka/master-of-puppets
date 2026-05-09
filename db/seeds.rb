# db/seeds.rb
#
# Minimal seed: one project, one admin, and a two-role agent tree
# (Orchestrator → Executor) wired to the Claude Code local adapter.
# Run: bin/rails db:seed
# This REPLACES all existing data.

puts "Seeding Director AI..."

ActiveRecord::Base.transaction do
  Session.destroy_all
  User.destroy_all
  Project.destroy_all

  user = User.create!(
    email_address: "admin@test.com",
    password: "111111111"
  )

  project = Project.create!(name: "Director AI")
  # after_create callback auto-seeds builtin skills and role categories.

  Membership.create!(user: user, project: project, role: :owner)

  categories = project.role_categories.index_by(&:name)

  adapter_config = { "model" => "claude-sonnet-4-20250514" }
  budget_period_start = Date.current.beginning_of_month

  orchestrator = Role.create!(
    project: project,
    title: "Orchestrator",
    description: "Delegates work to direct reports and coordinates execution.",
    job_spec: "You are the Orchestrator.",
    parent: nil,
    role_category: categories.fetch("Orchestrator"),
    adapter_type: :claude_local,
    adapter_config: adapter_config,
    status: :idle,
    budget_cents: 100_000,
    budget_period_start: budget_period_start
  )

  Role.create!(
    project: project,
    title: "Executor",
    description: "Executes tasks assigned by the Orchestrator and produces deliverables.",
    job_spec: "You are the Executor.",
    parent: orchestrator,
    role_category: categories.fetch("Executor"),
    adapter_type: :claude_local,
    adapter_config: adapter_config,
    status: :idle,
    budget_cents: 50_000,
    budget_period_start: budget_period_start
  )

  puts "  Created user: admin@director.ai"
  puts "  Created project: #{project.name}"
  puts "  Created 2 roles: Orchestrator → Executor"
end

puts "Done."
