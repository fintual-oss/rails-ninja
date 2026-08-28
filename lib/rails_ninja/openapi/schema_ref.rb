# frozen_string_literal: true

module RailsNinja
  module OpenAPI
    module SchemaRef
      module_function

      def to_json_schema(type)
        if type.is_a?(Array)
          inner = type.first
          {
            type: "array",
            items: to_json_schema(inner),
          }
        elsif type <= Schema::Base
          { "$ref" => "#/components/schemas/#{type.name || type.object_id}" }
        else
          primitive_type(type)
        end
      end

      def schema_to_json_schema(schema_class)
        properties = {}
        required = []

        schema_class._fields.each do |name, field|
          properties[name.to_s] = to_json_schema(field.type)
          required << name.to_s if field.required
        end

        result = { type: "object", properties: properties }
        result[:required] = required if required.any?
        result
      end

      def primitive_type(type)
        return type.openapi_schema if type.is_a?(Class) && type <= Types::BaseScalar

        raise Error, "Unsupported schema type: #{type.inspect}"
      end
    end
  end
end
