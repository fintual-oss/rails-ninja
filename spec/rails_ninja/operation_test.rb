# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class OperationTest < Minitest::Test
  def test_endpoint_summary_from_handler
    endpoint = RailsNinja::Operation.new(
      verb: :get,
      path: "/items",
      handler: :list_items,
      api_class: RailsNinja::API
    )

    assert_equal "List items", endpoint.summary
  end

  def test_endpoint_response_is_array
    schema = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
    end

    endpoint = RailsNinja::Operation.new(
      verb: :get,
      path: "/items",
      handler: :list_items,
      api_class: RailsNinja::API,
      response: [schema]
    )

    assert endpoint.response_is_array?
    assert_equal schema, endpoint.response_schema_class
  end

  def test_header_params_from_strings
    endpoint = RailsNinja::Operation.new(
      verb: :get,
      path: "/items",
      handler: :list_items,
      api_class: RailsNinja::API,
      headers: ["X-API-KEY", "X-MESSAGE-UUID"]
    )

    assert_equal 2, endpoint.header_params.size
    assert_equal "X-API-KEY", endpoint.header_params[0][:name]
    assert_equal true, endpoint.header_params[0][:required]
    assert_equal({ type: "string" }, endpoint.header_params[0][:schema])
    assert_equal "X-MESSAGE-UUID", endpoint.header_params[1][:name]
  end

  def test_header_params_from_hashes
    endpoint = RailsNinja::Operation.new(
      verb: :get,
      path: "/items",
      handler: :list_items,
      api_class: RailsNinja::API,
      headers: [
        { name: "X-API-KEY", type: "string", required: true },
        { name: "X-OPTIONAL", type: "integer", required: false },
      ]
    )

    assert_equal 2, endpoint.header_params.size
    assert_equal "X-API-KEY", endpoint.header_params[0][:name]
    assert_equal true, endpoint.header_params[0][:required]
    assert_equal "X-OPTIONAL", endpoint.header_params[1][:name]
    assert_equal false, endpoint.header_params[1][:required]
    assert_equal({ type: "integer" }, endpoint.header_params[1][:schema])
  end

  def test_header_params_default_to_empty
    endpoint = RailsNinja::Operation.new(
      verb: :get,
      path: "/items",
      handler: :list_items,
      api_class: RailsNinja::API
    )

    assert_equal [], endpoint.header_params
  end

  def test_class_level_headers_applied_to_endpoint
    api_class = Class.new(RailsNinja::API)
    api_class.ninja_headers "X-API-KEY", "X-TENANT-ID"

    endpoint = RailsNinja::Operation.new(
      verb: :get, path: "/items", handler: :list_items, api_class: api_class
    )

    assert_equal 2, endpoint.header_params.size
    assert_equal "X-API-KEY", endpoint.header_params[0][:name]
    assert_equal "X-TENANT-ID", endpoint.header_params[1][:name]
  end

  def test_class_level_headers_merged_with_endpoint_headers
    api_class = Class.new(RailsNinja::API)
    api_class.ninja_headers "X-API-KEY"

    endpoint = RailsNinja::Operation.new(
      verb: :get, path: "/items", handler: :list_items, api_class: api_class,
      headers: ["X-REQUEST-ID"]
    )

    assert_equal 2, endpoint.header_params.size
    assert_equal "X-API-KEY", endpoint.header_params[0][:name]
    assert_equal "X-REQUEST-ID", endpoint.header_params[1][:name]
  end

  def test_endpoint_headers_override_class_level_headers
    api_class = Class.new(RailsNinja::API)
    api_class.ninja_headers({ name: "X-API-KEY", required: true })

    endpoint = RailsNinja::Operation.new(
      verb: :get, path: "/items", handler: :list_items, api_class: api_class,
      headers: [{ name: "X-API-KEY", required: false }]
    )

    assert_equal 1, endpoint.header_params.size
    assert_equal "X-API-KEY", endpoint.header_params[0][:name]
    assert_equal false, endpoint.header_params[0][:required]
  end

  def test_with_tags_overrides_tags
    endpoint = RailsNinja::Operation.new(
      verb: :get, path: "/items", handler: :list_items, api_class: RailsNinja::API,
      tags: ["Original"]
    )

    assert_equal ["Original"], endpoint.tags

    endpoint.with_tags(["Overridden"])

    assert_equal ["Overridden"], endpoint.tags
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
