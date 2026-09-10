# frozen_string_literal: true

module RailsNinja
  module Types
    class File < BaseScalar
      class << self
        def valid?(value)
          value.respond_to?(:original_filename) && value.respond_to?(:read)
        end

        # Raw binary sits outside JSON Schema's type system, so OpenAPI 3.1+
        # describes it with contentMediaType and no `type`: a `type: string`
        # part with no contentEncoding defaults to text/plain, which would
        # contradict this keyword and get it discarded. The generator rewrites
        # this to `type: string, format: binary` for 3.0, which predates
        # contentMediaType.
        def openapi_schema
          { contentMediaType: "application/octet-stream" }
        end
      end
    end
  end
end
