class SkillsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "skills"
  end
end
