# frozen_string_literal: true

module RailsNinja
  module Response
    module_function

    def json(body, status: 200)
      [status, { "content-type" => "application/json" }, [MultiJson.dump(body)]]
    end

    def html(body, status: 200)
      [status, { "content-type" => "text/html" }, [body]]
    end

    def error(message, status:)
      json({ error: message }, status: status)
    end
  end
end
