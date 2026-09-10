# frozen_string_literal: true

module RailsNinja
  module Types
    class File < BaseScalar
      class << self
        def valid?(value)
          value.respond_to?(:original_filename) && value.respond_to?(:read)
        end

        def openapi_schema
          { type: "string", format: "binary" }
        end
      end
    end
  end
end
