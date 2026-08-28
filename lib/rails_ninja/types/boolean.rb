# frozen_string_literal: true

module RailsNinja
  module Types
    class Boolean < BaseScalar
      class << self
        def ruby_classes
          [TrueClass, FalseClass]
        end

        def openapi_schema
          { type: "boolean" }
        end
      end
    end
  end
end
