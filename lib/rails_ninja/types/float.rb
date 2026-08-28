# frozen_string_literal: true

module RailsNinja
  module Types
    class Float < BaseScalar
      class << self
        def ruby_classes
          [::Float]
        end

        def openapi_schema
          { type: "number" }
        end
      end
    end
  end
end
