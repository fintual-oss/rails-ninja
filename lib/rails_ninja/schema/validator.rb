# frozen_string_literal: true

module RailsNinja
  module Schema
    class Validator
      attr_reader :schema_class, :data

      def initialize(schema_class, data)
        @schema_class = schema_class
        @data = data || {}
      end

      def call
        errors = []
        validated = {}

        schema_class._fields.each do |name, field|
          value = data.key?(name) ? data[name] : data[name.to_s]

          if value.nil?
            if field.required && field.default.nil?
              errors << "#{name} is required"
              next
            end
            value = field.default
          end

          next if value.nil?

          result, validation_errors = validate_value(value, field.type)
          if validation_errors.any?
            errors.concat(validation_errors.map { |e| "#{name}#{e}" })
          else
            validated[name] = result
          end
        end

        [validated, errors]
      end

      private

      def validate_value(value, type)
        if array_type?(type)
          validate_array(value, type)
        elsif schema_type?(type)
          validate_schema(value, type)
        elsif scalar_type?(type)
          validate_scalar(value, type)
        else
          raise Error, "Unsupported schema type: #{type.inspect}"
        end
      end

      def validate_array(value, type)
        return [nil, [": Expected #{format_type(type)}, got #{value.class}"]] unless value.is_a?(Array)

        validated = []
        errors = []

        value.each_with_index do |item, index|
          result, item_errors = validate_value(item, type.first)
          if item_errors.any?
            errors.concat(item_errors.map { |e| "[#{index}]#{e}" })
          else
            validated << result
          end
        end

        [validated, errors]
      end

      def validate_scalar(value, type)
        return [value, []] if type.valid?(value)

        [nil, [": Expected #{type.type_name}, got #{value.class}"]]
      end

      def validate_schema(value, type)
        result, errors = type.validate(value)
        [result, errors.map { |err| ".#{err}" }]
      end

      def array_type?(type)
        type.is_a?(Array)
      end

      def schema_type?(type)
        type.is_a?(Class) && type <= Schema::Base
      end

      def scalar_type?(type)
        type.is_a?(Class) && type <= Types::BaseScalar
      end

      def format_type(type)
        return "[#{format_type(type.first)}]" if array_type?(type)
        return type.type_name if scalar_type?(type)

        type.name || type.to_s
      end
    end
  end
end
