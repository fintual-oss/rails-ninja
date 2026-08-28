# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class SchemaTest < Minitest::Test
  def setup
    @schema = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :email, RailsNinja::Types::String
      field :age, RailsNinja::Types::Int
    end
  end

  def test_field_registration
    assert_equal 3, @schema._fields.size
    assert_equal :name, @schema._fields[:name].name
    assert_equal RailsNinja::Types::String, @schema._fields[:name].type
  end

  def test_validate_valid_data
    validated, errors = @schema.validate({ name: "Alice", email: "alice@example.com", age: 30 })

    assert_empty errors
    assert_equal "Alice", validated[:name]
    assert_equal 30, validated[:age]
  end

  def test_validate_missing_required_field
    _, errors = @schema.validate({ name: "Alice" })

    assert_includes errors, "email is required"
    assert_includes errors, "age is required"
  end

  def test_validate_rejects_string_for_integer
    validated, errors = @schema.validate({ name: "Alice", email: "a@b.com", age: "25" })

    assert_includes errors, "age: Expected Integer, got String"
    refute validated.key?(:age)
  end

  def test_validate_array_of_primitives
    schema = Class.new(RailsNinja::Schema::Base) do
      field :ids, [RailsNinja::Types::Int]
    end

    validated, errors = schema.validate({ ids: [1, 2, 3] })

    assert_empty errors
    assert_equal [1, 2, 3], validated[:ids]
  end

  def test_validate_array_of_nested_schemas
    item = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
      field :name, RailsNinja::Types::String
    end
    schema = Class.new(RailsNinja::Schema::Base) do
      field :items, [item]
    end

    validated, errors = schema.validate({ items: [{ "id" => 1, "name" => "Book" }, { id: 2, name: "Pen" }] })

    assert_empty errors
    assert_equal [{ id: 1, name: "Book" }, { id: 2, name: "Pen" }], validated[:items]
  end

  def test_validate_array_reports_indexed_errors
    item = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
      field :name, RailsNinja::Types::String
    end
    schema = Class.new(RailsNinja::Schema::Base) do
      field :items, [item]
    end

    _, errors = schema.validate({ items: [{ name: "Book" }, { id: "bad", name: "Pen" }] })

    assert_includes errors, "items[0].id is required"
    assert_includes errors, "items[1].id: Expected Integer, got String"
  end

  def test_validate_array_rejects_non_array_value
    schema = Class.new(RailsNinja::Schema::Base) do
      field :ids, [RailsNinja::Types::Int]
    end

    _, errors = schema.validate({ ids: "1" })

    assert_includes errors, "ids: Expected [Integer], got String"
  end

  def test_validate_optional_field
    schema = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :nickname, RailsNinja::Types::String, required: false
    end

    validated, errors = schema.validate({ name: "Alice" })

    assert_empty errors
    assert_equal "Alice", validated[:name]
    refute validated.key?(:nickname)
  end

  def test_validate_default_value
    schema = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
      field :role, RailsNinja::Types::String, required: false, default: "user"
    end

    validated, errors = schema.validate({ name: "Alice" })

    assert_empty errors
    assert_equal "user", validated[:role]
  end

  def test_serialize_from_hash
    result = @schema.serialize({ name: "Alice", email: "a@b.com", age: 30 })

    assert_equal({ name: "Alice", email: "a@b.com", age: 30 }, result)
  end

  def test_serialize_from_object
    user = Struct.new(:name, :email, :age).new("Alice", "a@b.com", 30)
    result = @schema.serialize(user)

    assert_equal({ name: "Alice", email: "a@b.com", age: 30 }, result)
  end

  def test_serialize_array_of_primitives
    schema = Class.new(RailsNinja::Schema::Base) do
      field :ids, [RailsNinja::Types::Int]
    end

    result = schema.serialize({ ids: [1, 2, 3] })

    assert_equal({ ids: [1, 2, 3] }, result)
  end

  def test_serialize_array_of_nested_schemas
    item = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
      field :name, RailsNinja::Types::String
    end
    schema = Class.new(RailsNinja::Schema::Base) do
      field :items, [item]
    end
    item_data = Struct.new(:id, :name)

    result = schema.serialize({ items: [item_data.new(1, "Book"), { "id" => 2, "name" => "Pen" }] })

    assert_equal({ items: [{ id: 1, name: "Book" }, { id: 2, name: "Pen" }] }, result)
  end

  def test_serialize_many
    users = [
      { name: "Alice", email: "a@b.com", age: 30 },
      { name: "Bob", email: "b@b.com", age: 25 },
    ]

    result = @schema.serialize_many(users)

    assert_equal 2, result.size
    assert_equal "Alice", result[0][:name]
    assert_equal "Bob", result[1][:name]
  end

  def test_inherited_fields
    child = Class.new(@schema) do
      field :role, RailsNinja::Types::String
    end

    assert_equal 4, child._fields.size
    assert_equal 3, @schema._fields.size
  end

  def test_rejects_ruby_types
    error = assert_raises(RailsNinja::Error) do
      Class.new(RailsNinja::Schema::Base) do
        field :id, Integer
      end
    end

    assert_equal "Unsupported schema type: Integer", error.message
  end

  def test_validate_falsy_value_zero
    schema = Class.new(RailsNinja::Schema::Base) do
      field :count, RailsNinja::Types::Int
    end

    validated, errors = schema.validate({ count: 0 })

    assert_empty errors
    assert_equal 0, validated[:count]
  end

  def test_serialize_falsy_value_zero
    schema = Class.new(RailsNinja::Schema::Base) do
      field :count, RailsNinja::Types::Int
    end

    result = schema.serialize({ count: 0 })

    assert_equal 0, result[:count]
  end

  def test_validate_float_and_boolean_fields
    schema = Class.new(RailsNinja::Schema::Base) do
      field :price, RailsNinja::Types::Float
      field :active, RailsNinja::Types::Boolean
    end

    validated, errors = schema.validate({ price: 4.2, active: false })

    assert_empty errors
    assert_equal 4.2, validated[:price]
    assert_equal false, validated[:active]
  end

  def test_serialize_float_and_boolean_fields
    schema = Class.new(RailsNinja::Schema::Base) do
      field :price, RailsNinja::Types::Float
      field :active, RailsNinja::Types::Boolean
    end

    result = schema.serialize({ price: "4.2", active: 1 })

    assert_equal({ price: "4.2", active: 1 }, result)
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
