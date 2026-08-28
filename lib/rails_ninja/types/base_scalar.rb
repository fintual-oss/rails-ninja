# frozen_string_literal: true

module RailsNinja
  module Types
    class BaseScalar
      class << self
        def valid?(value)
          ruby_classes.any? { |ruby_class| value.is_a?(ruby_class) }
        end

        def openapi_schema
          raise NotImplementedError
        end

        def type_name
          name.split("::").last
        end

        def ruby_classes
          raise NotImplementedError
        end
      end
    end
  end
end
