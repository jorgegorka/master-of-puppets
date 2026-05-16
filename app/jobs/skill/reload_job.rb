class Skill::ReloadJob < ApplicationJob
  queue_as :default

  # When path is nil, walks the whole tree (boot-time replay).
  # When path is set, loads just that one file (supervisor watcher callback).
  def perform(path: nil)
    if path
      Skill.find_or_initialize_by(source_path: path).load_from_path!
    else
      Skill.reload_from_disk
    end
  end
end
