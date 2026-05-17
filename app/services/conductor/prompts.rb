module Conductor
  module Prompts
    TEMPLATES_DIR = Pathname.new(__dir__).join("prompts")

    module_function

    def decomposition(mission:, profiles:, user:)
      render("decomposition.erb",
             mission:   mission,
             profiles:  profiles,
             user:      user)
    end

    def render(name, locals)
      template = ERB.new(TEMPLATES_DIR.join(name).read, trim_mode: "-")
      binding = TOPLEVEL_BINDING.dup
      locals.each { |k, v| binding.local_variable_set(k, v) }
      template.result(binding)
    end
  end
end
