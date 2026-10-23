# frozen_string_literal: true

module RailsNinja
  module Schema
    Field = Struct.new(:name, :type, :required, :default, :enum, :documentation, keyword_init: true) do
      def initialize(name:, type:, required: true, default: nil, enum: nil, openapi: {}, **documentation)
        unknown = openapi.keys - %i[format pattern minLength maxLength minimum maximum default enum oneOf]
        raise ArgumentError, "Unsupported field OpenAPI keys: #{unknown.join(', ')}" if unknown.any?

        unknown = documentation.keys - %i[description example]
        raise ArgumentError, "Unsupported field documentation keys: #{unknown.join(', ')}" if unknown.any?

        super(name: name, type: type, required: required, default: default, enum: enum,
          documentation: openapi.merge(documentation).deep_dup)
      end
    end
  end
end
