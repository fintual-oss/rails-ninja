# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class PublicApi < RailsNinja::API
  title "Public API"
  version "1.0"

  schema :ProductOut do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  get "/products", response: [ProductOut]
  def list_products
    [{ id: 1, name: "Widget" }]
  end
end

class AdminApi < RailsNinja::API
  title "Admin API"
  version "2.0"

  schema :SettingOut do
    field :key, RailsNinja::Types::String
    field :value, RailsNinja::Types::String
  end

  get "/settings", response: [SettingOut]
  def list_settings
    [{ key: "mode", value: "production" }]
  end
end

# Group whose handler renders directly with a non-default status, content type, and body —
# used to verify the parent forwards all three when the handler has already performed.
class CustomRenderingChildGroup < RailsNinja::EndpointGroup
  get "/render"
  def render_directly
    self.status = 201
    self.content_type = "application/xml"
    self.response_body = ["<x>ok</x>"]
  end
end

class CustomRenderingParentApi < RailsNinja::API
  docs false
  mount CustomRenderingChildGroup, prefix: "/sub"
end

# Two groups that share a handler symbol (`:list`) at distinct paths —
# used to verify mounted dispatch resolves each handler independently.
class UsersGroup < RailsNinja::EndpointGroup
  get "/users"
  def list
    render_json([{ id: 1, kind: "user" }])
  end
end

class PostsGroup < RailsNinja::EndpointGroup
  get "/posts"
  def list
    render_json([{ id: 99, kind: "post" }])
  end
end

class CombinedApi < RailsNinja::API
  docs false
  mount UsersGroup, prefix: "/u"
  mount PostsGroup, prefix: "/p"
end

class MultiApiTest < Minitest::Test
  include Rack::Test::Methods

  def test_public_api_serves_its_endpoints
    with_app(PublicApi) do
      get "/products"
      assert_equal 200, last_response.status
      body = MultiJson.load(last_response.body, symbolize_keys: true)
      assert_equal "Widget", body[0][:name]
    end
  end

  def test_admin_api_serves_its_endpoints
    with_app(AdminApi) do
      get "/settings"
      assert_equal 200, last_response.status
      body = MultiJson.load(last_response.body, symbolize_keys: true)
      assert_equal "mode", body[0][:key]
    end
  end

  def test_public_api_does_not_have_admin_routes
    with_app(PublicApi) do
      get "/settings"
      assert_equal 404, last_response.status
    end
  end

  def test_admin_api_does_not_have_public_routes
    with_app(AdminApi) do
      get "/products"
      assert_equal 404, last_response.status
    end
  end

  def test_public_api_openapi_spec
    with_app(PublicApi) do
      get "/openapi.json"
      spec = MultiJson.load(last_response.body)
      assert_equal "Public API", spec["info"]["title"]
      assert_equal "1.0", spec["info"]["version"]
      assert spec["paths"]["/products"]
      refute spec["paths"]["/settings"]
    end
  end

  def test_admin_api_openapi_spec
    with_app(AdminApi) do
      get "/openapi.json"
      spec = MultiJson.load(last_response.body)
      assert_equal "Admin API", spec["info"]["title"]
      assert_equal "2.0", spec["info"]["version"]
      assert spec["paths"]["/settings"]
      refute spec["paths"]["/products"]
    end
  end

  def test_each_api_has_its_own_docs
    with_app(PublicApi) do
      get "/docs"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "swagger-ui"
    end

    with_app(AdminApi) do
      get "/docs"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "swagger-ui"
    end
  end

  def test_mounted_group_propagates_status_content_type_and_body
    with_app(CustomRenderingParentApi) do
      get "/sub/render"
      assert_equal 201, last_response.status
      assert_includes last_response.content_type, "application/xml"
      assert_equal "<x>ok</x>", last_response.body
    end
  end

  def test_mounted_groups_with_same_handler_name_dispatch_independently
    with_app(CombinedApi) do
      get "/u/users"
      assert_equal 200, last_response.status
      users_body = MultiJson.load(last_response.body, symbolize_keys: true)
      assert_equal "user", users_body[0][:kind]

      get "/p/posts"
      assert_equal 200, last_response.status
      posts_body = MultiJson.load(last_response.body, symbolize_keys: true)
      assert_equal "post", posts_body[0][:kind]
    end
  end

  private

  def with_app(app_class)
    @current_app = app_class
    yield
  ensure
    @current_app = nil
  end

  def app
    @current_app
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
