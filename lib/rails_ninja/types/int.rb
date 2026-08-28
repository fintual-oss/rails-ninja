# frozen_string_literal: true

module RailsNinja
  module Types
    class Int < BaseScalar
      class << self
        def ruby_classes
          [::Integer]
        end

        def openapi_schema
          { type: "integer" }
        end

        def type_name
          "Integer"
        end
      end
    end
  end
end
