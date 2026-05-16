module WorkspaceBootstrap
  SUBDIRS = %w[memory skills profiles artifacts logs].freeze
  SEED_MEMORY = "# Memory\n\nIndex of memory notes.\n"

  def self.run(root)
    pathname = Pathname.new(root)
    SUBDIRS.each { |sub| FileUtils.mkdir_p(pathname.join(sub)) }

    memory_md = pathname.join("memory/MEMORY.md")
    File.write(memory_md, SEED_MEMORY) unless memory_md.exist?
  end
end

Rails.application.config.after_initialize do
  next if Rails.env.test?

  WorkspaceBootstrap.run(Rails.application.config.x.mop_home)
end
