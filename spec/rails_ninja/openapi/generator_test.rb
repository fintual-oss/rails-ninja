# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class GeneratorTestApi < RailsNinja::API
  title "Test API"
  version "1.0"

  schema :ItemOut do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  schema :ItemIn do
    field :name, RailsNinja::Types::String
  end

  get "/items", response: [ItemOut]
  def list_items; end

  post "/items", request: ItemIn, response: ItemOut
  def create_item; end

  get "/items/:id", response: ItemOut
  def get_item; end
end

class HeaderGeneratorTestApi < RailsNinja::API
  title "Header Test API"
  version "1.0"

  get "/items", headers: ["X-API-KEY", "X-MESSAGE-UUID"]
  def list_items; end

  get "/items/:id", headers: [{ name: "X-API-KEY", required: true }, { name: "X-OPTIONAL", required: false }]
  def get_item; end

  post "/items"
  def create_item; end
end

class ServerGeneratorTestApi < RailsNinja::API
  title "Server Test API"
  version "1.0"
  server "/internal-api/test"

  get "/items"
  def list_items; end
end

class ApiKeySecurityGeneratorTestApi < RailsNinja::API
  openapi_security_scheme(
    :ApiKeyAuth,
    type: "apiKey",
    in: "header",
    name: "X-API-Key"
  )
  openapi_security :ApiKeyAuth

  get "/items"
  def list_items; end
end

class BearerSecurityGeneratorTestApi < RailsNinja::API
  openapi_security_scheme :UserAuth, type: "http", scheme: "bearer"
  openapi_security :UserAuth

  get "/items"
  def list_items; end
end

class GeneratorTest < Minitest::Test
  def setup
    @generator = RailsNinja::OpenAPI::Generator.new(GeneratorTestApi)
  end

  def test_spec_structure
    spec = @generator.to_hash

    assert_equal "3.2.0", spec[:openapi]
    assert_equal "Test API", spec[:info][:title]
    assert_equal "1.0", spec[:info][:version]
    assert spec[:paths]
    assert spec[:components][:schemas]
  end

  def test_openapi_version_can_be_selected
    spec = RailsNinja::OpenAPI::Generator.new(GeneratorTestApi, openapi_version: "3.1.0").to_hash

    assert_equal "3.1.0", spec[:openapi]
  end

  def test_rejects_unsupported_openapi_version
    error = assert_raises(ArgumentError) do
      RailsNinja::OpenAPI::Generator.new(GeneratorTestApi, openapi_version: "2.0")
    end

    assert_match "expected 3.0.x, 3.1.x, or 3.2.x", error.message
  end

  def test_servers_omitted_when_not_declared
    spec = @generator.to_hash

    refute spec.key?(:servers)
  end

  def test_servers_generated_when_declared
    spec = RailsNinja::OpenAPI::Generator.new(ServerGeneratorTestApi).to_hash

    assert_equal [{ url: "/internal-api/test" }], spec[:servers]
  end

  def test_paths_generated
    spec = @generator.to_hash

    assert spec[:paths]["/items"]
    assert spec[:paths]["/items/{id}"]
    assert spec[:paths]["/items"]["get"]
    assert spec[:paths]["/items"]["post"]
    assert spec[:paths]["/items/{id}"]["get"]
  end

  def test_api_key_security_scheme
    spec = RailsNinja::OpenAPI::Generator.new(ApiKeySecurityGeneratorTestApi).to_hash

    assert_equal({
                   "ApiKeyAuth" => {
                     type: "apiKey",
                     in: "header",
                     name: "X-API-Key",
                   },
                 }, spec[:components][:securitySchemes])
    assert_equal [{ "ApiKeyAuth" => [] }], spec[:security]
  end

  def test_bearer_security_scheme
    spec = RailsNinja::OpenAPI::Generator.new(BearerSecurityGeneratorTestApi).to_hash

    assert_equal({
                   "UserAuth" => {
                     type: "http",
                     scheme: "bearer",
                   },
                 }, spec[:components][:securitySchemes])
    assert_equal [{ "UserAuth" => [] }], spec[:security]
  end

  def test_request_body_generated
    spec = @generator.to_hash
    post_op = spec[:paths]["/items"]["post"]

    assert post_op[:requestBody]
    assert post_op[:requestBody][:content]["application/json"]
  end

  def test_response_schema_generated
    spec = @generator.to_hash
    get_op = spec[:paths]["/items"]["get"]

    response = get_op[:responses]["200"]
    assert response[:content]["application/json"]
    schema = response[:content]["application/json"][:schema]
    assert_equal "array", schema[:type]
  end

  def test_path_parameters_generated
    spec = @generator.to_hash
    get_op = spec[:paths]["/items/{id}"]["get"]

    assert get_op[:parameters]
    param = get_op[:parameters].first
    assert_equal "id", param[:name]
    assert_equal "path", param[:in]
    assert param[:required]
  end

  def test_component_schemas_use_short_names
    spec = @generator.to_hash
    schemas = spec[:components][:schemas]

    assert schemas["ItemOut"], "Expected schema named 'ItemOut'"
    assert schemas["ItemIn"], "Expected schema named 'ItemIn'"
  end

  def test_component_schemas_include_humanized_titles
    spec = @generator.to_hash
    item_out = spec[:components][:schemas]["ItemOut"]

    assert_equal "ItemOut", item_out[:title]
    assert_equal "Id", item_out[:properties]["id"][:title]
    assert_equal "Name", item_out[:properties]["name"][:title]
  end

  def test_property_titles_preserve_id_suffixes
    api = Class.new(RailsNinja::API)
    api.schema(:Request) do
      field :user_id, RailsNinja::Types::Int
      field :minimum_acceptable_mxn_amount, RailsNinja::Types::String
    end
    request_schema = api::Request
    api.class_eval do
      post "/x", request: request_schema
      define_method(:create) { nil }
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash
    properties = spec[:components][:schemas]["Request"][:properties]

    assert_equal "User Id", properties["user_id"][:title]
    assert_equal "Minimum Acceptable Mxn Amount", properties["minimum_acceptable_mxn_amount"][:title]
  end

  def test_schema_refs_use_short_names
    spec = @generator.to_hash
    get_op = spec[:paths]["/items"]["get"]

    response_schema = get_op[:responses]["200"][:content]["application/json"][:schema]
    assert_equal "#/components/schemas/ItemOut", response_schema[:items]["$ref"]
  end

  def test_operation_id_uses_tag_and_handler
    spec = @generator.to_hash

    # GeneratorTestApi endpoints get a tag derived from the class name
    get_op = spec[:paths]["/items"]["get"]
    assert get_op[:operationId]
    assert_includes get_op[:operationId], "list_items"
  end

  def test_operation_id_with_explicit_tags
    action = Class.new(RailsNinja::Endpoint) do
      post "/notify"
      def send_notification; end
    end

    api = Class.new(RailsNinja::API) do
      tags "Notifications"
    end
    api.include_endpoint(action)

    generator = RailsNinja::OpenAPI::Generator.new(api)

    spec = generator.to_hash
    post_op = spec[:paths]["/notify"]["post"]

    assert_equal "notifications_send_notification", post_op[:operationId]
  end

  def test_schema_name_clash_raises_error
    action1 = Class.new(RailsNinja::Endpoint)
    action1.schema(:Payload) { field :name, RailsNinja::Types::String }
    action1.post "/a", request: action1::Payload
    action1.class_eval { def handle_a; end }

    action2 = Class.new(RailsNinja::Endpoint)
    action2.schema(:Payload) { field :id, RailsNinja::Types::Int }
    action2.post "/b", request: action2::Payload
    action2.class_eval { def handle_b; end }

    api = Class.new(RailsNinja::API)
    api.include_endpoint(action1)
    api.include_endpoint(action2)

    generator = RailsNinja::OpenAPI::Generator.new(api)

    assert_raises(RailsNinja::Error) { generator.to_hash }
  end

  def test_same_schema_class_used_in_multiple_endpoints_does_not_clash
    schema = Class.new(RailsNinja::Schema::Base) { field :name, RailsNinja::Types::String }

    action1 = Class.new(RailsNinja::Endpoint)
    action1.const_set(:Shared, schema)
    action1._schemas[:Shared] = schema
    action1.post "/a", request: schema
    action1.class_eval { def handle_a; end }

    action2 = Class.new(RailsNinja::Endpoint)
    action2.const_set(:Shared, schema)
    action2._schemas[:Shared] = schema
    action2.post "/b", request: schema
    action2.class_eval { def handle_b; end }

    api = Class.new(RailsNinja::API)
    api.include_endpoint(action1)
    api.include_endpoint(action2)

    generator = RailsNinja::OpenAPI::Generator.new(api)

    spec = generator.to_hash
    assert spec[:components][:schemas]["Shared"]
  end

  def test_responses_map_emits_multiple_status_entries
    api = Class.new(RailsNinja::API)
    api.schema(:Ok) { field :value, RailsNinja::Types::String }
    api.schema(:Err) { field :error, RailsNinja::Types::String }
    ok_schema = api::Ok
    err_schema = api::Err
    api.class_eval do
      post "/x", responses: { 200 => ok_schema, 422 => err_schema, 404 => err_schema }
      define_method(:do_it) { nil }
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash
    responses = spec[:paths]["/x"]["post"][:responses]

    assert_equal "#/components/schemas/Ok", responses["200"][:content]["application/json"][:schema]["$ref"]
    assert_equal "#/components/schemas/Err", responses["422"][:content]["application/json"][:schema]["$ref"]
    assert_equal "#/components/schemas/Err", responses["404"][:content]["application/json"][:schema]["$ref"]
  end

  def test_one_of_emits_oneof_without_discriminator_when_not_provided
    api = Class.new(RailsNinja::API)
    api.schema(:A) { field :a_field, RailsNinja::Types::String }
    api.schema(:B) { field :b_field, RailsNinja::Types::Int }
    a_class = api::A
    b_class = api::B
    api.schema(:Wrapper) do
      field :variant, one_of(a_class, b_class), required: false
    end
    wrapper_class = api::Wrapper
    api.class_eval do
      get "/x", response: wrapper_class
      define_method(:get_it) { nil }
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash
    wrapper = spec[:components][:schemas]["Wrapper"]
    variant_prop = wrapper[:properties]["variant"]

    assert variant_prop["oneOf"]
    assert_equal 2, variant_prop["oneOf"].size
    assert_equal "#/components/schemas/A", variant_prop["oneOf"][0]["$ref"]
    assert_equal "#/components/schemas/B", variant_prop["oneOf"][1]["$ref"]
    refute variant_prop.key?("discriminator")

    assert spec[:components][:schemas]["A"]
    assert spec[:components][:schemas]["B"]
  end

  def test_one_of_with_discriminator_emits_mapping_and_enum_literals
    api = Class.new(RailsNinja::API)
    api.schema(:Cat) do
      field :kind, RailsNinja::Types::String, enum: ["cat"], default: "cat"
      field :purr, RailsNinja::Types::Boolean
    end
    api.schema(:Dog) do
      field :kind, RailsNinja::Types::String, enum: ["dog"], default: "dog"
      field :bark, RailsNinja::Types::Boolean
    end
    cat_class = api::Cat
    dog_class = api::Dog
    api.schema(:Pet) do
      field :animal, one_of(cat_class, dog_class, discriminator: :kind)
    end
    pet_class = api::Pet
    api.class_eval do
      get "/pet", response: pet_class
      define_method(:get_pet) { nil }
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash

    animal = spec[:components][:schemas]["Pet"][:properties]["animal"]
    assert animal["oneOf"]
    assert_equal({
                   "propertyName" => "kind",
                   "mapping" => {
                     "cat" => "#/components/schemas/Cat",
                     "dog" => "#/components/schemas/Dog",
                   },
                 }, animal["discriminator"])

    cat_kind = spec[:components][:schemas]["Cat"][:properties]["kind"]
    assert_equal ["cat"], cat_kind[:enum]
  end
end

class HeaderGeneratorTest < Minitest::Test
  def setup
    @generator = RailsNinja::OpenAPI::Generator.new(HeaderGeneratorTestApi)
  end

  def test_header_params_in_openapi_spec
    spec = @generator.to_hash
    get_op = spec[:paths]["/items"]["get"]

    headers = get_op[:parameters].select { |p| p[:in] == "header" }
    assert_equal 2, headers.size
    assert_equal "X-API-KEY", headers[0][:name]
    assert_equal "header", headers[0][:in]
    assert_equal true, headers[0][:required]
    assert_equal "X-MESSAGE-UUID", headers[1][:name]
  end

  def test_header_params_combined_with_path_params
    spec = @generator.to_hash
    get_op = spec[:paths]["/items/{id}"]["get"]

    path_params = get_op[:parameters].select { |p| p[:in] == "path" }
    header_params = get_op[:parameters].select { |p| p[:in] == "header" }

    assert_equal 1, path_params.size
    assert_equal "id", path_params[0][:name]
    assert_equal 2, header_params.size
    assert_equal "X-API-KEY", header_params[0][:name]
    assert_equal true, header_params[0][:required]
    assert_equal "X-OPTIONAL", header_params[1][:name]
    assert_equal false, header_params[1][:required]
  end

  def test_no_header_params_when_not_defined
    spec = @generator.to_hash
    post_op = spec[:paths]["/items"]["post"]

    assert_nil post_op[:parameters]
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
