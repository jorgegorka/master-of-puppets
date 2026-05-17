module AgentProfile::Loadable
  extend ActiveSupport::Concern

  class_methods do
    # Reads `db/seeds/agent_profiles.yml` and upserts each profile.
    # `body_digest` short-circuits unchanged rows so re-running the seed
    # is idempotent and event-free.
    def refresh_from_yaml!(path: Rails.root.join("db/seeds/agent_profiles.yml"))
      yaml = YAML.safe_load_file(path)
      Array(yaml["profiles"]).each do |entry|
        slug   = entry.fetch("slug")
        digest = Digest::SHA256.hexdigest(entry.to_yaml)
        profile = find_or_initialize_by(slug: slug)
        next if profile.persisted? && profile.body_digest == digest

        transaction do
          profile.assign_attributes(
            display_name: entry.fetch("display_name"),
            role:         entry.fetch("role"),
            model:        entry.fetch("model"),
            provider:     entry.fetch("provider"),
            specialties:  Array(entry["specialties"]),
            avoid_tasks:  Array(entry["avoid_tasks"]),
            cwd:          entry.fetch("cwd"),
            enabled:      entry.fetch("enabled", true),
            body_digest:  digest
          )
          profile.save!
          profile.track_event(profile.previously_new_record? ? :created : :updated)
        end
      end
    end
  end
end
