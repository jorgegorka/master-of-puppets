class ContentRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :content, reading: :content }
end
