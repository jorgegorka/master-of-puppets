class BaseAdapter
  # Run-centric contract. Adapters receive a Run + a pre-composed prompt;
  # they no longer compose prompts themselves.
  def self.execute(run:, prompt:, session_id: nil)
    raise NotImplementedError, "#{name} must implement .execute"
  end

  def self.test_connection(column)
    raise NotImplementedError, "#{name} must implement .test_connection"
  end

  def self.display_name
    raise NotImplementedError, "#{name} must implement .display_name"
  end

  def self.description
    raise NotImplementedError, "#{name} must implement .description"
  end

  def self.config_schema
    { required: [], optional: [] }
  end
end
