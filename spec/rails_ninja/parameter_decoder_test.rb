# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class ParameterDecoderTest < Minitest::Test
  def setup
    item = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
    end
    @schema = Class.new(RailsNinja::Schema::Base) do
      field :count, RailsNinja::Types::Int
      field :price, RailsNinja::Types::Float
      field :active, RailsNinja::Types::Boolean
      field :name, RailsNinja::Types::String
      field :ids, [RailsNinja::Types::Int]
      field :item, item
    end
  end

  def test_decodes_url_encoded_scalar_values
    decoded = decode(count: "42", price: "4.2", active: "false", name: "Widget")

    assert_equal 42, decoded[:count]
    assert_equal 4.2, decoded[:price]
    assert_equal false, decoded[:active]
    assert_equal "Widget", decoded[:name]
  end

  def test_decodes_array_and_nested_values
    decoded = decode(ids: %w[1 2], item: { id: "3" })

    assert_equal [1, 2], decoded[:ids]
    assert_equal({ id: 3 }, decoded[:item])
  end

  def test_leaves_noncanonical_values_for_the_validator
    decoded = decode(count: "01", price: "1.2.3", active: "1")

    assert_equal "01", decoded[:count]
    assert_equal "1.2.3", decoded[:price]
    assert_equal "1", decoded[:active]
  end

  private

  def decode(data)
    RailsNinja::Schema::ParameterDecoder.new(@schema, data).call
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
