# frozen_string_literal: true

module RailsNinja
  module Schema
    class ParameterDecoder
      INTEGER_PATTERN = /\A-?(?:0|[1-9]\d*)\z/
      NUMBER_PATTERN = /\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/

      attr_reader :schema_class, :data

      def initialize(schema_class, data)
        @schema_class = schema_class
        @data = data || {}
      end

      def call
        schema_class._fields.each_with_object({}) do |(name, field), decoded|
          next unless data.key?(name) || data.key?(name.to_s)

          value = data.key?(name) ? data[name] : data[name.to_s]
          decoded[name] = decode_value(value, field.type)
        end
      end

      private

      def decode_value(value, type)
        if type.is_a?(Array)
          value.is_a?(Array) ? value.map { |item| decode_value(item, type.first) } : value
        elsif type.is_a?(Class) && type <= Schema::Base
          value.is_a?(Hash) ? self.class.new(type, value).call : value
        elsif type.is_a?(Class) && type <= Types::BaseScalar
          decode_scalar(value, type)
        else
          value
        end
      end

      def decode_scalar(value, type)
        return value unless value.is_a?(::String)

        case type.openapi_schema[:type]
        when "integer" then decode_integer(value)
        when "number" then decode_number(value)
        when "boolean" then decode_boolean(value)
        else value
        end
      end

      def decode_integer(value)
        INTEGER_PATTERN.match?(value) ? Kernel.Integer(value, 10) : value
      end

      def decode_number(value)
        NUMBER_PATTERN.match?(value) ? Kernel.Float(value) : value
      end

      def decode_boolean(value)
        return true if value == "true"
        return false if value == "false"

        value
      end
    end
  end
end
