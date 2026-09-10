# frozen_string_literal: true

module RailsNinja
  module Types
    class File < BaseScalar
      class << self
        def valid?(value)
          value.respond_to?(:original_filename) && value.respond_to?(:read)
        end

        # OpenAPI 3.1+ prescribes `contentMediaType` with no `type` for raw
        # binary, but client tooling (openapi-generator < 7.23, Swagger UI for
        # arrays) still keys off `format: binary`, so emit that on every version.
        # TODO: emit contentMediaType for 3.1+ once the tooling catches up.
        def openapi_schema
          { type: "string", format: "binary" }
        end
      end
    end
  end
end
