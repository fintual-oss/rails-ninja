# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class SchemaRefTest < Minitest::Test
  def test_string_field
    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema(RailsNinja::Types::String)

    assert_equal({ type: "string" }, result)
  end

  def test_integer_field
    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema(RailsNinja::Types::Int)

    assert_equal({ type: "integer" }, result)
  end

  def test_float_field
    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema(RailsNinja::Types::Float)

    assert_equal({ type: "number" }, result)
  end

  def test_boolean_field
    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema(RailsNinja::Types::Boolean)

    assert_equal({ type: "boolean" }, result)
  end

  def test_schema_ref
    schema = Class.new(RailsNinja::Schema::Base)
    # Give it a name so the ref is predictable
    Object.const_set(:TestRefSchema, schema) unless defined?(TestRefSchema)

    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema(TestRefSchema)

    assert_equal({ "$ref" => "#/components/schemas/TestRefSchema" }, result)
  end

  def test_array_of_primitives
    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema([RailsNinja::Types::String])

    assert_equal({ type: "array", items: { type: "string" } }, result)
  end

  def test_array_of_schema
    schema = Class.new(RailsNinja::Schema::Base)
    Object.const_set(:TestArraySchema, schema) unless defined?(TestArraySchema)

    result = RailsNinja::OpenAPI::SchemaRef.to_json_schema([TestArraySchema])

    assert_equal "array", result[:type]
    assert_equal "#/components/schemas/TestArraySchema", result[:items]["$ref"]
  end

  def test_schema_to_json_schema_with_required_fields
    schema = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :age, RailsNinja::Types::Int
    end

    result = RailsNinja::OpenAPI::SchemaRef.schema_to_json_schema(schema)

    assert_equal "object", result[:type]
    assert_equal({ type: "string" }, result[:properties]["name"])
    assert_equal({ type: "integer" }, result[:properties]["age"])
    assert_includes result[:required], "name"
    assert_includes result[:required], "age"
  end

  def test_schema_to_json_schema_with_optional_fields
    schema = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :nickname, RailsNinja::Types::String, required: false
    end

    result = RailsNinja::OpenAPI::SchemaRef.schema_to_json_schema(schema)

    assert_equal 2, result[:properties].size
    assert_equal ["name"], result[:required]
  end

  def test_schema_to_json_schema_without_required_fields
    schema = Class.new(RailsNinja::Schema::Base) do
      field :nickname, RailsNinja::Types::String, required: false
    end

    result = RailsNinja::OpenAPI::SchemaRef.schema_to_json_schema(schema)

    refute result.key?(:required)
  end

  def test_schema_to_json_schema_with_nested_schema
    inner = Class.new(RailsNinja::Schema::Base) do
      field :street, RailsNinja::Types::String
    end
    Object.const_set(:TestAddressSchema, inner) unless defined?(TestAddressSchema)

    outer = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :address, TestAddressSchema
    end

    result = RailsNinja::OpenAPI::SchemaRef.schema_to_json_schema(outer)

    assert_equal({ type: "string" }, result[:properties]["name"])
    assert_equal({ "$ref" => "#/components/schemas/TestAddressSchema" }, result[:properties]["address"])
  end

  def test_schema_to_json_schema_with_array_field
    item = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
    end
    Object.const_set(:TestItemSchema, item) unless defined?(TestItemSchema)

    schema = Class.new(RailsNinja::Schema::Base) do
      field :items, [TestItemSchema]
    end

    result = RailsNinja::OpenAPI::SchemaRef.schema_to_json_schema(schema)

    items_prop = result[:properties]["items"]
    assert_equal "array", items_prop[:type]
    assert_equal "#/components/schemas/TestItemSchema", items_prop[:items]["$ref"]
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
