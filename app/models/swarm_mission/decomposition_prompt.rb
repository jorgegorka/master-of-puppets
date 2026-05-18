class SwarmMission::DecompositionPrompt
  TEMPLATE_PATH = Rails.root.join("app/models/swarm_mission/decomposition_prompt.erb")

  attr_reader :mission, :profiles, :user

  def initialize(mission:, profiles:, user:)
    @mission, @profiles, @user = mission, profiles, user
  end

  def to_s
    ERB.new(TEMPLATE_PATH.read, trim_mode: "-").result(binding)
  end
end
