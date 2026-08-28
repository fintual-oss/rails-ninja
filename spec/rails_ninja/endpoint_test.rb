# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class ListItems < RailsNinja::Endpoint
  schema :ItemOut do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  get "/items", response: [ItemOut]
  def handle
    [{ id: 1, name: "Widget" }, { id: 2, name: "Gadget" }]
  end
end

class CreateItem < RailsNinja::Endpoint
  schema :ItemIn do
    field :name, RailsNinja::Types::String
  end

  schema :ItemCreated do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  post "/items", request: ItemIn, response: ItemCreated
  def handle
    { id: 3, name: params[:name] }
  end
end

class GetItem < RailsNinja::Endpoint
  schema :ItemDetail do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  get "/items/:id", response: ItemDetail
  def handle
    { id: params[:id].to_i, name: "Widget" }
  end
end

class EndpointDemoApi < RailsNinja::API
  title "Endpoint Demo"
  version "1.0"

  include_endpoint ListItems
  include_endpoint CreateItem
  include_endpoint GetItem
end

class EndpointTest < Minitest::Test
  include Rack::Test::Methods

  def app
    EndpointDemoApi
  end

  def test_endpoint_registers_operation
    assert_equal 1, ListItems._endpoints.size
    op = ListItems._endpoints.first
    assert_equal :get, op.verb
    assert_equal "/items", op.path
    assert_equal :handle, op.handler
  end

  def test_api_pulls_in_endpoints
    assert_equal 3, EndpointDemoApi._endpoints.size
    verbs = EndpointDemoApi._endpoints.map(&:verb)
    assert_includes verbs, :get
    assert_includes verbs, :post
  end

  def test_get_endpoint
    get "/items"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 2, body.size
    assert_equal "Widget", body[0][:name]
  end

  def test_post_endpoint
    post "/items",
         MultiJson.dump({ name: "Sprocket" }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "Sprocket", body[:name]
    assert_equal 3, body[:id]
  end

  def test_post_endpoint_validates_request
    post "/items",
         MultiJson.dump({}),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 422, last_response.status
  end

  def test_endpoint_with_path_params
    get "/items/7"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 7, body[:id]
  end

  def test_endpoint_schemas_dont_collide
    assert ListItems.const_defined?(:ItemOut)
    assert CreateItem.const_defined?(:ItemIn)
    assert CreateItem.const_defined?(:ItemCreated)
    refute ListItems.const_defined?(:ItemIn)
  end

  def test_openapi_includes_endpoints
    get "/openapi.json"

    spec = MultiJson.load(last_response.body)
    assert spec["paths"]["/items"]
    assert spec["paths"]["/items"]["get"]
    assert spec["paths"]["/items"]["post"]
    assert spec["paths"]["/items/{id}"]
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
