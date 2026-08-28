# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class ApiTest < Minitest::Test
  def test_endpoint_registration_with_get
    api = Class.new(RailsNinja::API) do
      get "/items"
      def list_items
        []
      end
    end

    assert_equal 1, api._endpoints.size
    endpoint = api._endpoints.first
    assert_equal :get, endpoint.verb
    assert_equal "/items", endpoint.path
    assert_equal :list_items, endpoint.handler
  end

  def test_endpoint_registration_with_post_and_schemas
    item_in = Class.new(RailsNinja::Schema::Base) do
      field :name, RailsNinja::Types::String
    end

    item_out = Class.new(RailsNinja::Schema::Base) do
      field :id, RailsNinja::Types::Int
      field :name, RailsNinja::Types::String
    end

    api = Class.new(RailsNinja::API)
    api.post "/items", request: item_in, response: item_out
    api.class_eval do
      def create_item
        { id: 1, name: params[:name] }
      end
    end

    assert_equal 1, api._endpoints.size
    endpoint = api._endpoints.first
    assert_equal :post, endpoint.verb
    assert_equal "/items", endpoint.path
    assert endpoint.request_schema
    assert endpoint.response_schema
  end

  def test_multiple_endpoints
    api = Class.new(RailsNinja::API) do
      get "/a"
      def method_a; end

      post "/b"
      def method_b; end

      put "/c"
      def method_c; end

      patch "/d"
      def method_d; end

      delete "/e"
      def method_e; end
    end

    assert_equal 5, api._endpoints.size
    verbs = api._endpoints.map(&:verb)
    assert_equal %i[get post put patch delete], verbs
  end

  def test_deprecated_paths_register_extra_endpoints
    api = Class.new(RailsNinja::API) do
      post "/items", deprecated_paths: "/legacy_items"
      def create_item; end
    end

    assert_equal 2, api._endpoints.size

    primary = api._endpoints.find { |ep| ep.path == "/items" }
    deprecated = api._endpoints.find { |ep| ep.path == "/legacy_items" }

    refute_nil primary
    refute_nil deprecated

    # Both route to the same handler and verb
    assert_equal :create_item, primary.handler
    assert_equal :create_item, deprecated.handler
    assert_equal :post, deprecated.verb

    refute primary.deprecated?
    assert deprecated.deprecated?
  end

  def test_deprecated_paths_accepts_an_array
    api = Class.new(RailsNinja::API) do
      get "/items", deprecated_paths: ["/old_items", "/legacy_items"]
      def list_items
        []
      end
    end

    assert_equal 3, api._endpoints.size
    deprecated_paths = api._endpoints.select(&:deprecated?).map(&:path)
    assert_equal ["/old_items", "/legacy_items"], deprecated_paths
  end

  def test_deprecated_path_is_dispatchable
    api = Class.new(RailsNinja::API) do
      get "/items", deprecated_paths: "/legacy_items"
      def list_items
        { ok: true }
      end
    end

    env = Rack::MockRequest.env_for("/legacy_items", method: "GET")
    status, = api.call(env)
    assert_equal 200, status
  end

  def test_openapi_marks_deprecated_paths
    api = Class.new(RailsNinja::API) do
      post "/items", deprecated_paths: "/legacy_items"
      def create_item; end
    end

    paths = RailsNinja::OpenAPI::Generator.new(api).to_hash[:paths]

    refute paths["/items"]["post"].key?(:deprecated)
    assert_equal true, paths["/legacy_items"]["post"][:deprecated]

    # Only the current path carries an operationId; the deprecated alias omits it
    assert paths["/items"]["post"].key?(:operationId)
    refute paths["/legacy_items"]["post"].key?(:operationId)
  end

  def test_regular_methods_not_registered
    api = Class.new(RailsNinja::API) do
      get "/items"
      def list_items; end

      def helper_method; end
    end

    assert_equal 1, api._endpoints.size
  end

  def test_schema_registered_as_constant
    api = Class.new(RailsNinja::API) do
      schema :UserOut do
        field :id, RailsNinja::Types::Int
        field :name, RailsNinja::Types::String
      end
    end

    assert api.const_defined?(:UserOut)
    assert_equal 2, api::UserOut._fields.size
  end

  def test_title_and_version
    api = Class.new(RailsNinja::API) do
      title "My API"
      version "2.0"
    end

    assert_equal "My API", api._title
    assert_equal "2.0", api._version
  end

  def test_inherited_api_has_separate_endpoints
    parent = Class.new(RailsNinja::API) do
      get "/parent"
      def parent_method; end
    end

    child = Class.new(parent) do
      get "/child"
      def child_method; end
    end

    assert_equal 1, parent._endpoints.size
    assert_equal 1, child._endpoints.size
  end

  def test_docs_enabled_by_default
    api = Class.new(RailsNinja::API)
    assert api._docs_enabled?
  end

  def test_docs_can_be_disabled
    api = Class.new(RailsNinja::API) do
      docs false
    end
    refute api._docs_enabled?
  end

  def test_docs_disabled_hides_endpoints
    api = Class.new(RailsNinja::API) do
      docs false

      get "/items"
      def list_items
        []
      end
    end

    env = Rack::MockRequest.env_for("/docs", method: "GET")
    status, = api.call(env)
    assert_equal 404, status

    env = Rack::MockRequest.env_for("/openapi.json", method: "GET")
    status, = api.call(env)
    assert_equal 404, status
  end

  def test_rack_interface
    api = Class.new(RailsNinja::API) do
      get "/hello"
      def hello
        { message: "world" }
      end
    end

    assert api.respond_to?(:call)
  end

  def test_responds_to_make_response
    api = Class.new(RailsNinja::API)
    assert api.respond_to?(:make_response!)
  end

  def test_responds_to_dispatch
    api = Class.new(RailsNinja::API)
    assert api.respond_to?(:dispatch)
  end

  def test_tags_dsl
    api = Class.new(RailsNinja::API) do
      tags "Notifications"
    end

    assert_equal ["Notifications"], api._tags
  end

  def test_tags_default_to_nil
    api = Class.new(RailsNinja::API)
    assert_nil api._tags
  end

  def test_tags_with_multiple_values
    api = Class.new(RailsNinja::API) do
      tags "Notifications", "Internal"
    end

    assert_equal ["Notifications", "Internal"], api._tags
  end

  def test_action_inherits_api_tags
    action_class = Class.new(RailsNinja::Endpoint) do
      get "/items"
      def handle; end
    end

    api = Class.new(RailsNinja::API) do
      tags "MyGroup"
    end
    api.include_endpoint(action_class)

    endpoint = api._endpoints.first
    assert_equal ["MyGroup"], endpoint.tags
  end

  def test_action_keeps_own_tags_when_api_has_no_tags
    action_class = Class.new(RailsNinja::Endpoint) do
      get "/items", tags: ["Custom"]
      def handle; end
    end

    api = Class.new(RailsNinja::API)
    api.include_endpoint(action_class)

    endpoint = api._endpoints.first
    assert_equal ["Custom"], endpoint.tags
  end

  def test_unique_handler_name_differs_per_source_class
    api1 = Class.new(RailsNinja::API)
    api2 = Class.new(RailsNinja::API)

    refute_equal api1._unique_handler_name(api1, :show),
                 api2._unique_handler_name(api2, :show)
  end

  def test_draw_routes_uses_unique_handlers_for_mounted_groups_with_shared_handler_name
    group1 = Class.new(RailsNinja::EndpointGroup) do
      get "/items"
      def list; end
    end
    group2 = Class.new(RailsNinja::EndpointGroup) do
      get "/things"
      def list; end
    end
    parent = Class.new(RailsNinja::API) do
      docs false
    end
    parent.mount group1, prefix: "/a"
    parent.mount group2, prefix: "/b"

    recorder = Class.new do
      attr_reader :matches

      def initialize
        @matches = []
      end

      def match(path, **opts)
        @matches << opts.merge(path: path)
      end
    end.new

    parent.draw_routes(recorder)

    handlers = recorder.matches.map { |m| m[:to].split("#").last }
    assert_equal 2, handlers.size
    assert_equal 2, handlers.uniq.size, "draw_routes must register a unique handler per mounted group endpoint"
  end

  def test_mount_rejects_api_classes
    sub = Class.new(RailsNinja::API) do
      docs false
      get "/items"
      def list; end
    end
    parent = Class.new(RailsNinja::API) do
      docs false
    end

    error = assert_raises(RailsNinja::Error) { parent.mount sub, prefix: "/sub" }
    assert_match(/cannot be mounted/, error.message)
    assert_match(/RailsNinja::EndpointGroup/, error.message)
  end

  def test_mount_rejects_non_group_values
    parent = Class.new(RailsNinja::API) do
      docs false
    end

    assert_raises(RailsNinja::Error) { parent.mount String, prefix: "/sub" }
    assert_raises(RailsNinja::Error) { parent.mount "not a class", prefix: "/sub" }
  end

  def test_api_subclasses_are_registered_but_groups_are_not
    api = Class.new(RailsNinja::API) do
      docs false
    end
    group = Class.new(RailsNinja::EndpointGroup)

    assert_includes RailsNinja.registered_apis, api
    refute_includes RailsNinja.registered_apis, group
  end

  def test_draw_routes_handlers_match_methods_defined_by_mount_for_included_endpoints
    endpoint1 = Class.new(RailsNinja::Endpoint) do
      post "/foo"
      def handle_foo; end
    end
    endpoint2 = Class.new(RailsNinja::Endpoint) do
      post "/bar"
      def handle_bar; end
    end
    sub = Class.new(RailsNinja::EndpointGroup)
    sub.include_endpoint(endpoint1)
    sub.include_endpoint(endpoint2)

    parent = Class.new(RailsNinja::API) do
      docs false
    end
    parent.mount sub, prefix: "/sub"

    recorder = Class.new do
      attr_reader :matches

      def initialize
        @matches = []
      end

      def match(path, **opts)
        @matches << opts.merge(path: path)
      end
    end.new

    parent.draw_routes(recorder)

    route_handlers = recorder.matches.map { |m| m[:to].split("#").last.to_sym }
    parent_methods = parent.instance_methods(false)
    route_handlers.each do |h|
      assert_includes parent_methods, h,
                      "draw_routes registered handler #{h.inspect} but mount did not define a matching method " \
                      "on the parent"
    end
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
