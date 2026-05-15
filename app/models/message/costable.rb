module Message::Costable
  extend ActiveSupport::Concern

  # Cost computation lands in Task 1.9 (Llm::Pricing).
  # This module exists so Message can `include Message::Costable` from the start.
end
