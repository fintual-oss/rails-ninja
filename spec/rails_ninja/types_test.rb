# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class TypesTest < Minitest::Test
  def test_scalars_only_accept_their_ruby_types
    assert RailsNinja::Types::Int.valid?(2**63)
    assert RailsNinja::Types::String.valid?("42")
    assert RailsNinja::Types::Float.valid?(4.2)
    assert RailsNinja::Types::Boolean.valid?(true)
    assert RailsNinja::Types::Boolean.valid?(false)

    refute RailsNinja::Types::Int.valid?("42")
    refute RailsNinja::Types::String.valid?(42)
    refute RailsNinja::Types::Float.valid?("4.2")
    refute RailsNinja::Types::Float.valid?(4)
    refute RailsNinja::Types::Boolean.valid?(1)
    refute RailsNinja::Types::Boolean.valid?("true")
  end

  def test_scalars_expose_their_openapi_schemas
    assert_equal({ type: "boolean" }, RailsNinja::Types::Boolean.openapi_schema)
    assert_equal({ type: "number" }, RailsNinja::Types::Float.openapi_schema)
    assert_equal({ type: "integer" }, RailsNinja::Types::Int.openapi_schema)
    assert_equal({ type: "string" }, RailsNinja::Types::String.openapi_schema)
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
