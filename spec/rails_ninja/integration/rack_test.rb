# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

UserData = Struct.new(:id, :name, :email)

USERS = [
  UserData.new(1, "Alice", "alice@example.com"),
  UserData.new(2, "Bob", "bob@example.com"),
]

class TestApi < RailsNinja::API
  title "Test API"
  version "1.0"

  schema :UserOut do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
    field :email, RailsNinja::Types::String
  end

  schema :UserIn do
    field :name, RailsNinja::Types::String
    field :email, RailsNinja::Types::String
    field :active, RailsNinja::Types::Boolean, required: false
  end

  get "/users", response: [UserOut]
  def list_users
    USERS
  end

  get "/users/:id", response: UserOut
  def get_user
    USERS.find { |u| u.id == params[:id].to_i }
  end

  post "/users", request: UserIn, response: UserOut
  def create_user
    UserData.new(3, params[:name], params[:email])
  end

  get "/hello"
  def hello
    { message: "world" }
  end

  # Mirrors a real handler whose last expression is an incidental object
  # (e.g. the return value of SomeJob.perform_later) that must NOT leak
  # into the response body.
  get "/fire_and_forget"
  def fire_and_forget
    Object.new
  end
end

class RackIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TestApi
  end

  def test_get_list
    get "/users"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 2, body.size
    assert_equal "Alice", body[0][:name]
  end

  def test_get_with_path_param
    get "/users/1"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 1, body[:id]
    assert_equal "Alice", body[:name]
  end

  def test_post_with_body
    post "/users",
         MultiJson.dump({ name: "Charlie", email: "charlie@example.com" }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "Charlie", body[:name]
    assert_equal 3, body[:id]
  end

  def test_post_validation_error
    post "/users",
         MultiJson.dump({ name: "Charlie" }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 422, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert body[:errors]
  end

  def test_post_rejects_integer_for_boolean
    post "/users",
         MultiJson.dump({ name: "Charlie", email: "charlie@example.com", active: 1 }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 422, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal ["active: Expected Boolean, got Integer"], body[:errors]
  end

  def test_get_without_schema_returns_empty_body
    get "/hello"

    assert_equal 200, last_response.status
    assert_empty last_response.body
  end

  def test_handler_return_value_does_not_leak_into_body
    get "/fire_and_forget"

    assert_equal 200, last_response.status
    assert_empty last_response.body
  end

  def test_not_found
    get "/nonexistent"

    assert_equal 404, last_response.status
  end

  def test_openapi_spec
    get "/openapi.json"

    assert_equal 200, last_response.status
    spec = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "3.2.0", spec[:openapi]
    assert_equal "Test API", spec[:info][:title]
    assert spec[:paths]
  end

  def test_swagger_ui
    get "/docs"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "swagger-ui"
  end
end

class AncestorBeforeActionsTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @sub_group = Class.new(RailsNinja::EndpointGroup) do
      get "/items"
      def list_items
        { items: [1, 2, 3] }
      end
    end

    @root_api = Class.new(RailsNinja::API) do
      before_action :check_token

      define_method(:check_token) do
        head :unauthorized unless request.headers["X-Token"] == "valid"
      end
    end
    @root_api.mount @sub_group, prefix: "/sub"

    @current_app = @root_api
  end

  def app
    @current_app
  end

  def test_root_before_action_halts_mounted_group
    get "/sub/items"

    assert_equal 401, last_response.status
  end

  def test_root_before_action_passes_with_valid_header
    get "/sub/items", {}, { "HTTP_X_TOKEN" => "valid" }

    assert_equal 200, last_response.status
    assert_empty last_response.body
  end

  def test_root_before_action_halts_with_render_json
    root = Class.new(RailsNinja::API) do
      before_action :verify

      define_method(:verify) do
        render_json({ error: "Forbidden" }, status: 403) unless request.headers["X-Token"] == "valid"
      end
    end

    sub = Class.new(RailsNinja::EndpointGroup) do
      get "/data"
      def data
        { ok: true }
      end
    end

    root.mount sub, prefix: "/sub"
    @current_app = root

    get "/sub/data"

    assert_equal 403, last_response.status
    parsed = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "Forbidden", parsed[:error]
  end

  def test_root_before_action_applies_to_included_endpoints
    endpoint = Class.new(RailsNinja::Endpoint) do
      get "/items"
      def handle
        { ok: true }
      end
    end

    sub = Class.new(RailsNinja::EndpointGroup)
    sub.include_endpoint(endpoint)

    root = Class.new(RailsNinja::API) do
      before_action :check_token

      define_method(:check_token) do
        head :unauthorized unless request.headers["X-Token"] == "valid"
      end
    end
    root.mount sub, prefix: "/sub"
    @current_app = root

    get "/sub/items"
    assert_equal 401, last_response.status

    get "/sub/items", {}, { "HTTP_X_TOKEN" => "valid" }
    assert_equal 200, last_response.status
  end

  def test_mounted_group_before_action_still_runs
    sub = Class.new(RailsNinja::EndpointGroup) do
      before_action :sub_check

      define_method(:sub_check) do
        head :forbidden unless request.headers["X-Role"] == "admin"
      end

      get "/secret"
      def secret
        { secret: true }
      end
    end

    root = Class.new(RailsNinja::API) do
      before_action :root_check

      define_method(:root_check) do
        head :unauthorized unless request.headers["X-Token"] == "valid"
      end
    end
    root.mount sub, prefix: "/sub"
    @current_app = root

    # Missing both headers
    get "/sub/secret"
    assert_equal 401, last_response.status

    # Valid token but missing role
    get "/sub/secret", {}, { "HTTP_X_TOKEN" => "valid" }
    assert_equal 403, last_response.status

    # Both valid
    get "/sub/secret", {}, { "HTTP_X_TOKEN" => "valid", "HTTP_X_ROLE" => "admin" }
    assert_equal 200, last_response.status
  end
end

class StrictTypesIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    @app
  end

  def test_validated_values_available_in_params
    count_schema = Class.new(RailsNinja::Schema::Base) do
      field :count, RailsNinja::Types::Int
    end

    echo_schema = Class.new(RailsNinja::Schema::Base) do
      field :received, RailsNinja::Types::Int
      field :type, RailsNinja::Types::String
    end

    api = Class.new(RailsNinja::API)
    api.post "/count", request: count_schema, response: echo_schema
    api.class_eval do
      def set_count
        { received: params[:count], type: params[:count].class.name }
      end
    end

    @app = api

    post "/count",
         MultiJson.dump({ count: 42 }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 42, body[:received]
    assert_equal "Integer", body[:type]
  end

  def test_url_encoded_form_values_are_decoded
    define_echo_api(:post)

    post "/values", { count: "42", price: "4.2", active: "false", name: "Widget" }

    assert_decoded_response
  end

  def test_query_values_are_decoded
    define_echo_api(:get)

    get "/values", { count: "42", price: "4.2", active: "false", name: "Widget" }

    assert_decoded_response
  end

  def test_numeric_boolean_query_value_is_rejected
    define_echo_api(:get)

    get "/values", { count: "42", price: "4.2", active: "1", name: "Widget" }

    assert_equal 422, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal ["active: Expected Boolean, got String"], body[:errors]
  end

  def test_json_string_is_not_decoded_to_integer
    define_echo_api(:post)

    post "/values",
         MultiJson.dump({ count: "42", price: 4.2, active: false, name: "Widget" }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 422, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal ["count: Expected Integer, got String"], body[:errors]
  end

  private

  def define_echo_api(verb)
    input_schema = Class.new(RailsNinja::Schema::Base) do
      field :count, RailsNinja::Types::Int
      field :price, RailsNinja::Types::Float
      field :active, RailsNinja::Types::Boolean
      field :name, RailsNinja::Types::String
    end
    output_schema = Class.new(input_schema)

    @app = Class.new(RailsNinja::API) do
      public_send(verb, "/values", request: input_schema, response: output_schema)

      define_method(:echo) do
        params.slice(:count, :price, :active, :name)
      end
    end
  end

  def assert_decoded_response
    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal({ count: 42, price: 4.2, active: false, name: "Widget" }, body)
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
