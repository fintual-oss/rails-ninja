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

  def test_multipart_files_are_accepted_singly_and_in_arrays
    upload_schema = Class.new(RailsNinja::Schema::Base) do
      field :avatar, RailsNinja::Types::File
      field :attachments, [RailsNinja::Types::File]
      field :caption, RailsNinja::Types::String
    end

    @app = Class.new(RailsNinja::API) do
      post "/uploads", request: upload_schema

      define_method(:upload) do
        render_json({
          avatar: params[:avatar].original_filename,
          attachments: params[:attachments].map(&:read),
          caption: params[:caption],
        })
      end
    end

    file = ->(name, body) { Rack::Test::UploadedFile.new(StringIO.new(body), "text/plain", original_filename: name) }
    post "/uploads", { avatar: file.call("me.txt", "x"), attachments: [file.call("a", "A"), file.call("b", "B")], caption: "hi" }

    assert_equal 200, last_response.status, last_response.body
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal({ avatar: "me.txt", attachments: %w[A B], caption: "hi" }, body)

    post "/uploads", { avatar: "not-a-file", attachments: [file.call("a", "A")], caption: "hi" }

    assert_equal 422, last_response.status
    assert_equal ["avatar: Expected File, got String"], MultiJson.load(last_response.body, symbolize_keys: true)[:errors]
  end

  def test_raw_multipart_with_repeated_names_and_json_object_part
    metadata_schema = Class.new(RailsNinja::Schema::Base) { field :title, RailsNinja::Types::String }
    upload_schema = Class.new(RailsNinja::Schema::Base) do
      field :files, [RailsNinja::Types::File]
      field :metadata, metadata_schema
    end

    @app = Class.new(RailsNinja::API) do
      post "/uploads", request: upload_schema

      define_method(:upload) do
        render_json({ files: params[:files].map(&:read), title: params[:metadata][:title] })
      end
    end

    body = multipart_part("files", "A", filename: "a.txt") + multipart_part("files", "B", filename: "b.txt") +
      multipart_part("metadata", '{"title":"hi"}') + "--B--\r\n"

    post "/uploads", body, "CONTENT_TYPE" => "multipart/form-data; boundary=B"

    assert_equal 200, last_response.status, last_response.body
    assert_equal({ files: %w[A B], title: "hi" }, MultiJson.load(last_response.body, symbolize_keys: true))

    body = multipart_part("files", "A", filename: "a.txt") + multipart_part("metadata", "not json") + "--B--\r\n"
    post "/uploads", body, "CONTENT_TYPE" => "multipart/form-data; boundary=B"

    assert_equal 422, last_response.status
    assert_equal ["metadata: Expected object, got String"], MultiJson.load(last_response.body, symbolize_keys: true)[:errors]
  end

  def test_validated_files_reach_handlers_in_mounted_groups_and_included_endpoints
    upload_schema = Class.new(RailsNinja::Schema::Base) { field :files, [RailsNinja::Types::File] }
    endpoint = Class.new(RailsNinja::Endpoint) do
      post "/included", request: upload_schema
      define_method(:handle) { render_json({ files: params[:files].map(&:read) }) }
    end
    group = Class.new(RailsNinja::EndpointGroup) do
      post "/mounted", request: upload_schema
      define_method(:upload) { render_json({ files: params[:files].map(&:read) }) }
    end
    @app = Class.new(RailsNinja::API) do
      include_endpoint endpoint
      mount group, prefix: "/g"
    end
    body = multipart_part("files", "A", filename: "a.txt") + multipart_part("files", "B", filename: "b.txt") + "--B--\r\n"

    %w[/included /g/mounted].each do |path|
      post path, body, "CONTENT_TYPE" => "multipart/form-data; boundary=B"

      assert_equal 200, last_response.status, "#{path}: #{last_response.body}"
      assert_equal({ files: %w[A B] }, MultiJson.load(last_response.body, symbolize_keys: true))
    end
  end

  def test_repeated_bare_names_outside_multipart_are_still_rejected
    tags_schema = Class.new(RailsNinja::Schema::Base) { field :tags, [RailsNinja::Types::String] }
    @app = Class.new(RailsNinja::API) do
      get "/tags", request: tags_schema
      define_method(:list) { render_json(params[:tags]) }
      post "/tags", request: tags_schema
      define_method(:create) { render_json(params[:tags]) }
    end

    get "/tags?tags=a&tags=b"
    assert_equal 422, last_response.status

    post "/tags", "tags=a&tags=b", "CONTENT_TYPE" => "application/x-www-form-urlencoded"
    assert_equal 422, last_response.status
  end

  def test_json_object_part_is_validated_with_native_types
    metadata_schema = Class.new(RailsNinja::Schema::Base) do
      field :ids, [RailsNinja::Types::Int]
      field :count, RailsNinja::Types::Int
    end
    upload_schema = Class.new(RailsNinja::Schema::Base) { field :metadata, metadata_schema }
    @app = Class.new(RailsNinja::API) do
      post "/uploads", request: upload_schema
      define_method(:upload) { render_json(params[:metadata]) }
    end
    send_metadata = lambda do |json|
      post "/uploads", multipart_part("metadata", json) + "--B--\r\n", "CONTENT_TYPE" => "multipart/form-data; boundary=B"
      last_response.status
    end

    assert_equal 200, send_metadata.call('{"ids":[1,2],"count":3}')
    assert_equal 422, send_metadata.call('{"ids":1,"count":3}')
    assert_equal 422, send_metadata.call('{"ids":null,"count":3}')
    assert_equal 422, send_metadata.call('{"ids":[1],"count":"3"}')
  end

  def test_repeated_files_survive_a_non_rewindable_input_stream
    skip "needs Rack >= 3.1 (cached form pairs)" if Rack.release < "3.1"

    @app = repeated_files_app { request.request_parameters } # consume the stream first, like Rack::MethodOverride

    post "/uploads", two_files_body, "CONTENT_TYPE" => "multipart/form-data; boundary=B",
      "rack.input" => non_rewindable_io(two_files_body)

    assert_equal 200, last_response.status, last_response.body
    assert_equal %w[a.txt b.txt], MultiJson.load(last_response.body)
  end

  def test_reparse_path_rebuilds_repeated_names_and_keeps_earlier_tempfiles
    seen = []
    @app = repeated_files_app do
      seen << request.request_parameters["files"].tempfile
      request.env.delete("rack.request.form_pairs") # Rack < 3.1 shape: no cached pairs, rewindable input
    end

    post "/uploads", two_files_body, "CONTENT_TYPE" => "multipart/form-data; boundary=B"

    assert_equal 200, last_response.status, last_response.body
    assert_equal %w[a.txt b.txt], MultiJson.load(last_response.body)
    assert_includes last_request.env["rack.tempfiles"], seen.first
  end

  def test_multipart_without_pairs_or_rewind_only_fails_for_list_fields
    skip "Rack 2 requires rewindable input itself" if Rack.release < "3"

    list_schema = Class.new(RailsNinja::Schema::Base) { field :files, [RailsNinja::Types::File] }
    single_schema = Class.new(RailsNinja::Schema::Base) { field :file, RailsNinja::Types::File }
    @app = Class.new(RailsNinja::API) do
      before_action { request.request_parameters; request.env.delete("rack.request.form_pairs") } # Rack 3.0 shape
      post "/list", request: list_schema
      define_method(:list) { render_json(params[:files].map(&:original_filename)) }
      post "/single", request: single_schema
      define_method(:single) { render_json(params[:file].original_filename) }
    end

    error = assert_raises(RailsNinja::Error) do
      post "/list", two_files_body, "CONTENT_TYPE" => "multipart/form-data; boundary=B",
        "rack.input" => non_rewindable_io(two_files_body)
    end
    assert_match(/rewindable/, error.message)

    body = multipart_part("file", "A", filename: "a.txt") + "--B--\r\n"
    post "/single", body, "CONTENT_TYPE" => "multipart/form-data; boundary=B", "rack.input" => non_rewindable_io(body)

    assert_equal 200, last_response.status, last_response.body
    assert_equal "a.txt", MultiJson.load(last_response.body)
  end

  # An empty multipart body has no parts at all. Rack 3.1 then records no form pairs,
  # so this exercises the fallback to Rails' own parse.
  def test_empty_multipart_body_is_handled
    required_schema = Class.new(RailsNinja::Schema::Base) { field :file, RailsNinja::Types::File }
    optional_schema = Class.new(RailsNinja::Schema::Base) { field :file, RailsNinja::Types::File, required: false }
    @app = Class.new(RailsNinja::API) do
      post "/required", request: required_schema
      define_method(:required) { render_json({}) }
      post "/optional", request: optional_schema
      define_method(:optional) { render_json({ file: params.key?(:file) }) }
    end

    [
      { "CONTENT_TYPE" => "multipart/form-data; boundary=B" },
      { "CONTENT_TYPE" => "multipart/form-data" },
      # e.g. curl --data-binary '' on a server whose input stream cannot rewind
      { "CONTENT_TYPE" => "multipart/form-data; boundary=B", "CONTENT_LENGTH" => "0", "rack.input" => non_rewindable_io("") },
    ].each do |env|
      next if env.key?("rack.input") && Rack.release < "3" # Rack 2 itself requires a rewindable input

      post "/required", "", env

      assert_equal 422, last_response.status, env.inspect
      assert_equal ["file is required"], MultiJson.load(last_response.body, symbolize_keys: true)[:errors]

      post "/optional", "", env

      assert_equal 200, last_response.status, env.inspect
      assert_equal({ file: false }, MultiJson.load(last_response.body, symbolize_keys: true))
    end
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

  # Hand-built multipart part: openapi-generator clients repeat the bare name
  # for arrays and JSON-encode object properties, unlike Rack::Test.
  def repeated_files_app(&before)
    upload_schema = Class.new(RailsNinja::Schema::Base) { field :files, [RailsNinja::Types::File] }
    Class.new(RailsNinja::API) do
      before_action(&before)
      post "/uploads", request: upload_schema
      define_method(:upload) { render_json(params[:files].map(&:original_filename)) }
    end
  end

  def two_files_body
    multipart_part("files", "A", filename: "a.txt") + multipart_part("files", "B", filename: "b.txt") + "--B--\r\n"
  end

  def non_rewindable_io(body)
    Struct.new(:io) do
      def read(*args) = io.read(*args)
      def gets = io.gets
      def each(&block) = io.each(&block)
    end.new(StringIO.new(body))
  end

  def multipart_part(name, body, filename: nil)
    disposition = "form-data; name=\"#{name}\""
    disposition += "; filename=\"#{filename}\"" if filename
    "--B\r\nContent-Disposition: #{disposition}\r\n\r\n#{body}\r\n"
  end

  def assert_decoded_response
    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal({ count: 42, price: 4.2, active: false, name: "Widget" }, body)
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
