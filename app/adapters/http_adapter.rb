class HttpAdapter < BaseAdapter
  class PermanentError < StandardError; end
  class TransientError < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  MAX_RETRIES  = 3
  BASE_BACKOFF = 1

  def self.display_name
    "HTTP API"
  end

  def self.description
    "Connect to a cloud-hosted agent via HTTP POST requests"
  end

  def self.config_schema
    { required: %w[url], optional: %w[method headers auth_token timeout] }
  end

  def self.execute(run:, prompt:, session_id: nil)
    column = run.column
    url = column.adapter_config["url"]
    raise PermanentError, "No URL configured" if url.blank?

    payload = build_payload(run: run, prompt: prompt, session_id: session_id)
    response = deliver_with_retries(url, payload, column.adapter_config)

    {
      exit_code: 0,
      response_code: response.code.to_i,
      response_body: response.body&.truncate(1000)
    }
  end

  def self.backoff_sleep(seconds)
    sleep(seconds)
  end

  private_class_method def self.build_payload(run:, prompt:, session_id:)
    column = run.column
    task = run.task
    {
      column_id: column.id,
      column_name: column.name,
      run_id: run.id,
      trigger_type: run.trigger_type,
      task: task ? {
        id: task.id,
        title: task.title,
        description: task.description
      }.compact : nil,
      prompt: prompt,
      session_id: session_id,
      delivered_at: Time.current.iso8601
    }.compact
  end

  private_class_method def self.deliver_with_retries(url, payload, config)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    if config["timeout"].present?
      http.read_timeout = [ config["timeout"].to_i, 120 ].min
    end

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    config["headers"]&.each { |k, v| request[k] = v }
    request["Authorization"] = "Bearer #{config["auth_token"]}" if config["auth_token"].present?
    request.body = payload.to_json

    last_error = nil
    MAX_RETRIES.times do |attempt|
      begin
        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          return response
        elsif response.is_a?(Net::HTTPClientError)
          raise PermanentError, "HTTP #{response.code}: #{response.body&.truncate(200)}"
        else
          last_error = TransientError.new("HTTP #{response.code}: #{response.body&.truncate(200)}")
        end
      rescue PermanentError
        raise
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
        last_error = TransientError.new(e.message)
      end

      backoff_sleep(BASE_BACKOFF * (2 ** attempt)) if attempt + 1 < MAX_RETRIES
    end

    raise last_error || TransientError.new("Delivery failed after #{MAX_RETRIES} attempts")
  end
end
