# db/seeds.rb
#
# Minimal seed: one admin user, one project. Default columns are seeded by
# Project after_create. Run: bin/rails db:seed
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
  Membership.create!(user: user, project: project, role: :owner)

  puts "  Created user: #{user.email_address}"
  puts "  Created project: #{project.name}"
  puts "  Default columns:"
  project.columns.ordered.each { |c| puts "    - #{c.name} (#{c.transition_policy})" }
end

puts "Done."
