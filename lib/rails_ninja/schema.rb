# frozen_string_literal: true

module RailsNinja
  module Schema
    class Base
      class << self
        def field(name, type, required: true, default: nil, enum: nil, **documentation)
          validate_type!(type)
          _fields[name.to_sym] = Field.new(
            name: name.to_sym,
            type: type,
            required: required,
            default: default,
            enum: enum,
            **documentation
          )
        end

        def one_of(*variants, discriminator: nil)
          OneOf.new(variants, discriminator: discriminator)
        end

        def _fields
          @_fields ||= {}
        end

        def openapi(**documentation)
          unknown = documentation.keys - %i[description example]
          raise ArgumentError, "Unsupported schema documentation keys: #{unknown.join(', ')}" if unknown.any?

          @_openapi ||= {}
          @_openapi.merge!(documentation.deep_dup)
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_fields, _fields.dup)
          subclass.instance_variable_set(:@_openapi, openapi.deep_dup)
        end

        def validate(data)
          Validator.new(self, data).call
        end

        def serialize(object)
          Serializer.new(self, object).call
        end

        def serialize_many(collection)
          collection.map { |obj| serialize(obj) }
        end

        private

        def validate_type!(type)
          if type.is_a?(Array)
            raise Error, "List types must contain exactly one type" unless type.one?

            validate_type!(type.first)
          elsif type.is_a?(OneOf)
            type.variants.each { |variant| validate_type!(variant) }
          elsif type.is_a?(Class) && (type <= Base || type <= Types::BaseScalar)
            return
          else
            raise Error, "Unsupported schema type: #{type.inspect}"
          end
        end
      end
    end
  end
end
