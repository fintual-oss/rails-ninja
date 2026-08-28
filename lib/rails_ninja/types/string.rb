# frozen_string_literal: true

module RailsNinja
  module Types
    class String < BaseScalar
      class << self
        def ruby_classes
          [::String]
        end

        def openapi_schema
          { type: "string" }
        end
      end
    end
  end
end
