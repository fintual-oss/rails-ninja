# frozen_string_literal: true

module RailsNinja
  module Schema
    class Serializer
      attr_reader :schema_class, :object

      def initialize(schema_class, object)
        @schema_class = schema_class
        @object = object
      end

      def call
        result = {}

        schema_class._fields.each do |name, field|
          value = read_attribute(object, name)
          result[name] = serialize_value(value, field.type)
        end

        result
      end

      private

      def serialize_value(value, type)
        return nil if value.nil?

        if type.is_a?(OneOf)
          variant = pick_variant(type, value)
          variant ? Serializer.new(variant, value).call : value
        elsif array_type?(type)
          value.map { |item| serialize_value(item, type.first) }
        elsif schema_type?(type)
          Serializer.new(type, value).call
        elsif scalar_type?(type)
          value
        else
          raise Error, "Unsupported schema type: #{type.inspect}"
        end
      end

      def pick_variant(one_of, value)
        return nil unless value.is_a?(Hash)

        one_of.variants.find do |variant|
          variant._fields.each_value.all? do |field|
            !field.required || value.key?(field.name) || value.key?(field.name.to_s)
          end
        end
      end

      def read_attribute(obj, name)
        if obj.is_a?(Hash)
          obj.key?(name) ? obj[name] : obj[name.to_s]
        elsif obj.respond_to?(name)
          obj.public_send(name)
        elsif obj.respond_to?(:[])
          obj[name]
        end
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
    end
  end
end
