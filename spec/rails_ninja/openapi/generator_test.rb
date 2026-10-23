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

  def test_schema_and_field_documentation_is_generated_from_declarations
    api = Class.new(RailsNinja::API)
    api.schema(:Documented, description: "A documented record", example: { enabled: false, code: "ABC" }) do
      field :enabled, RailsNinja::Types::Boolean, description: "Whether enabled", example: false
      field :code, RailsNinja::Types::String, description: "Record code", example: "ABC",
        openapi: { pattern: "^[A-Z]+$", minLength: 1, maxLength: 10 }
    end
    schema = api::Documented
    api.get "/record", response: schema
    api.define_method(:read) { nil }

    result = RailsNinja::OpenAPI::Generator.new(api).to_hash[:components][:schemas]["Documented"]

    assert_equal({
      type: "object", title: "Documented", description: "A documented record",
      example: { enabled: false, code: "ABC" }, required: ["enabled", "code"],
      properties: {
        "enabled" => { type: "boolean", title: "Enabled", description: "Whether enabled", example: false },
        "code" => { type: "string", title: "Code", description: "Record code", example: "ABC",
                    pattern: "^[A-Z]+$", minLength: 1, maxLength: 10 }
      }
    }, result)
    assert_equal({ enabled: false, code: "ABC" }, schema.serialize(enabled: false, code: "ABC"))
    assert_equal [{ enabled: false, code: "ABC" }, []], schema.validate(enabled: false, code: "ABC")
  end

  def test_legacy_declarations_keep_the_same_operation_shape
    operation = @generator.to_hash[:paths]["/items"]["post"]

    assert_equal({
      summary: "Create item", operationId: "create_item",
      responses: { "200" => { description: "Successful response",
                              content: { "application/json" => {
                                schema: { "$ref" => "#/components/schemas/ItemOut" }
                              } } } },
      requestBody: { required: true, content: { "application/json" => {
        schema: { "$ref" => "#/components/schemas/ItemIn" }
      } } }
    }, operation)
  end

  def test_documentation_preserves_openapi_versions
    api = Class.new(RailsNinja::API)
    api.schema(:VersionedRecord, description: "Record") do
      field :name, RailsNinja::Types::String, example: "One"
    end
    api.get "/records", responses: { 200 => { schema: api::VersionedRecord, description: "Record found" } }
    api.define_method(:read) { nil }

    %w[3.0.3 3.1.0 3.2.0].each do |version|
      spec = RailsNinja::OpenAPI::Generator.new(api, openapi_version: version).to_hash

      assert_equal version, spec[:openapi]
      assert_equal "Record", spec[:components][:schemas]["VersionedRecord"][:description]
      assert_equal "Record found", spec[:paths]["/records"]["get"][:responses]["200"][:description]
    end
  end

  def test_schema_documentation_is_copied_on_inheritance
    parent = Class.new(RailsNinja::Schema::Base) do
      openapi description: "Parent", example: { name: "One" }
      field :name, RailsNinja::Types::String
    end
    child = Class.new(parent)
    child.openapi(description: "Child")
    child.openapi[:example][:name] = "Two"

    assert_equal({ description: "Parent", example: { name: "One" } }, parent.openapi)
    assert_equal({ description: "Child", example: { name: "Two" } }, child.openapi)
  end

  def test_query_header_and_path_documentation_preserves_parameter_identity
    api = Class.new(RailsNinja::API)
    api.schema(:Search) do
      field :limit, RailsNinja::Types::Int, required: false, description: "Page size", example: 0,
        openapi: { minimum: 0, maximum: 200, default: 40 }
    end
    api.get "/items/:id", request: api::Search,
      path_params: { id: { description: "Item ID", example: "item:1", schema: { pattern: "^item:[0-9]+$" } } },
      headers: [{ name: "X-Tenant", required: true, description: "Tenant ID", example: "abc",
                  schema: { type: "string", minLength: 1 } }]
    api.define_method(:read) { nil }

    operation = RailsNinja::OpenAPI::Generator.new(api).to_hash[:paths]["/items/{id}"]["get"]

    assert_equal [
      { name: "id", in: "path", required: true, description: "Item ID", example: "item:1",
        schema: { type: "string", pattern: "^item:[0-9]+$" } },
      { name: "X-Tenant", in: "header", required: true, description: "Tenant ID", example: "abc",
        schema: { type: "string", minLength: 1 } },
      { name: "limit", in: "query", required: false, description: "Page size", example: 0,
        schema: { type: "integer", minimum: 0, maximum: 200, default: 40 } }
    ], operation[:parameters]
  end

  def test_operation_response_and_api_documentation
    api = Class.new(RailsNinja::API)
    api.title "Documented API"
    api.description "Read records"
    api.openapi_tag "Records", description: "Record reads"
    api.schema(:ReadError) { field :error, RailsNinja::Types::String }
    error = api::ReadError
    api.get "/records", operation_id: "readRecords", description: "Read all records", tags: ["Records"],
      responses: {
        429 => { schema: error, description: "Wait before retrying", example: { error: "Too many requests" },
                 headers: { "Retry-After" => { description: "Seconds to wait", schema: { type: "integer" }, example: 1 } } }
      }
    api.define_method(:read) { nil }

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash
    operation = spec[:paths]["/records"]["get"]

    assert_equal "Read records", spec[:info][:description]
    assert_equal [{ name: "Records", description: "Record reads" }], spec[:tags]
    assert_equal "readRecords", operation[:operationId]
    assert_equal "Read all records", operation[:description]
    assert_equal({
      "429" => {
        description: "Wait before retrying",
        headers: { "Retry-After" => { description: "Seconds to wait", schema: { type: "integer" }, example: 1 } },
        content: { "application/json" => { schema: { "$ref" => "#/components/schemas/ReadError" },
                                          example: { error: "Too many requests" } } }
      }
    }, operation[:responses])
    assert_equal({ 429 => error }, api._endpoints.first.responses_map)
  end

  def test_multiple_response_examples_and_request_description
    api = Class.new(RailsNinja::API)
    api.schema(:Payload) { field :name, RailsNinja::Types::String }
    schema = api::Payload
    examples = { first: { value: [{ name: "One" }] }, second: { value: [{ name: "Two" }] } }
    api.post "/records", request: schema, request_description: "New record",
      responses: { 200 => { schema: [schema], examples: examples } }
    api.define_method(:create) { nil }

    operation = RailsNinja::OpenAPI::Generator.new(api).to_hash[:paths]["/records"]["post"]

    assert_equal "New record", operation[:requestBody][:description]
    assert_equal({ schema: { type: "array", items: { "$ref" => "#/components/schemas/Payload" } },
                   examples: examples }, operation[:responses]["200"][:content]["application/json"])
    assert_equal [schema], api._endpoints.first.response_schema
  end

  def test_documentation_does_not_mutate_or_leak_between_apis
    parent = Class.new(RailsNinja::API)
    parent.openapi_tag "Parent", description: "Parent records"
    child = Class.new(parent)
    child.openapi_tag "Child", description: "Child records"
    parent.get "/records", responses: { 200 => RailsNinja::Types::String }
    parent.define_method(:read) { "value" }
    generator = RailsNinja::OpenAPI::Generator.new(parent)
    first = generator.to_hash
    first[:tags].first[:description] = "Changed"

    assert_equal [{ name: "Parent", description: "Parent records" }], generator.to_hash[:tags]
    assert_equal 2, child._openapi_tags.size
    assert_equal 1, parent._openapi_tags.size
  end

  def test_unknown_field_schema_overrides_are_rejected
    error = assert_raises(ArgumentError) do
      Class.new(RailsNinja::Schema::Base) do
        field :name, RailsNinja::Types::String, openapi: { type: "integer" }
      end
    end

    assert_equal "Unsupported field OpenAPI keys: type", error.message
  end

  def test_unknown_path_parameter_annotations_are_rejected
    api = Class.new(RailsNinja::API)
    api.get "/records/:id", path_params: { wrong: { description: "Wrong name" } }
    api.define_method(:read) { nil }

    error = assert_raises(ArgumentError) { RailsNinja::OpenAPI::Generator.new(api).to_hash }

    assert_equal "Unknown path parameter annotations: wrong", error.message
  end

  def test_response_examples_are_mutually_exclusive
    error = assert_raises(ArgumentError) do
      RailsNinja::Operation.new(verb: :get, path: "/", handler: :read, api_class: RailsNinja::API,
        responses: { 200 => { schema: RailsNinja::Types::String, example: "one", examples: { two: { value: "two" } } } })
    end

    assert_equal "Response 200 cannot declare both example and examples", error.message
  end

  def test_rich_response_declarations_preserve_request_and_response_serialization
    api = Class.new(RailsNinja::API)
    api.schema(:Record) do
      field :name, RailsNinja::Types::String, description: "Record name", example: "One",
        openapi: { minLength: 3 }
    end
    api.post "/records", request: api::Record,
      responses: { 200 => { schema: api::Record, description: "Created record" } }
    api.define_method(:create) { { name: params[:name], internal: "hidden" } }

    response = Rack::MockRequest.new(api).post("/records",
      "CONTENT_TYPE" => "application/json", input: '{"name":"A"}')

    assert_equal 200, response.status
    assert_equal({ "name" => "A" }, MultiJson.load(response.body))
  end

  def test_mounted_path_metadata_and_deprecated_aliases
    endpoint = Class.new(RailsNinja::Endpoint)
    endpoint.get "/records/:id", deprecated_paths: "/old-records/:id", operation_id: "readRecord",
      path_params: { tenant: { description: "Tenant" }, id: { example: "123" } }
    endpoint.define_method(:read) { nil }
    api = Class.new(RailsNinja::API)
    api.mount endpoint, prefix: "/tenants/:tenant"

    paths = RailsNinja::OpenAPI::Generator.new(api).to_hash[:paths]
    operation = paths["/tenants/{tenant}/records/{id}"]["get"]

    assert_equal "readRecord", operation[:operationId]
    assert_equal [
      { name: "tenant", in: "path", required: true, schema: { type: "string" }, description: "Tenant" },
      { name: "id", in: "path", required: true, schema: { type: "string" }, example: "123" }
    ], operation[:parameters]
    refute paths["/tenants/{tenant}/old-records/{id}"]["get"].key?(:operationId)
    assert_equal true, paths["/tenants/{tenant}/old-records/{id}"]["get"][:deprecated]
  end

  def test_response_union_registers_every_schema_and_keeps_null_example
    api = Class.new(RailsNinja::API)
    api.schema(:SingleError) { field :error, RailsNinja::Types::String }
    api.schema(:ManyErrors) { field :errors, [RailsNinja::Types::String] }
    api.get "/records", responses: {
      422 => { schema: RailsNinja::Schema::OneOf.new([api::SingleError, api::ManyErrors]),
               examples: { single: { value: { error: "Invalid" } } } }
    }
    api.define_method(:read) { nil }
    api.schema(:OptionalRecord, example: nil) do
      field :name, RailsNinja::Types::String, required: false, example: nil
    end
    api.get "/optional", response: api::OptionalRecord
    api.define_method(:optional) { {} }

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash

    assert_equal %w[ManyErrors OptionalRecord SingleError], spec[:components][:schemas].keys.sort
    assert_equal({ "oneOf" => [
      { "$ref" => "#/components/schemas/SingleError" },
      { "$ref" => "#/components/schemas/ManyErrors" }
    ] }, spec[:paths]["/records"]["get"][:responses]["422"][:content]["application/json"][:schema])
    optional = spec[:components][:schemas]["OptionalRecord"]
    assert optional.key?(:example)
    assert_nil optional[:example]
    assert optional[:properties]["name"].key?(:example)
    assert_nil optional[:properties]["name"][:example]
  end

  def test_request_body_with_file_field_is_multipart
    upload_schema = Class.new(RailsNinja::Schema::Base) do
      field :files, [RailsNinja::Types::File]
    end
    upload_schema.define_singleton_method(:name) { "UploadIn" }
    api = Class.new(RailsNinja::API) do
      post "/uploads", request: upload_schema
      def upload; end
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash
    content = spec[:paths]["/uploads"]["post"][:requestBody][:content]

    assert_equal ["multipart/form-data"], content.keys
    assert_equal({ type: "string", format: "binary" }, spec[:components][:schemas]["UploadIn"][:properties]["files"][:items])
  end

  def test_file_subclass_is_multipart_and_nested_file_is_rejected
    image = Class.new(RailsNinja::Types::File)
    image.define_singleton_method(:name) { "Image" }
    upload_schema = Class.new(RailsNinja::Schema::Base) { field :image, image }
    upload_schema.define_singleton_method(:name) { "ImageIn" }
    api = Class.new(RailsNinja::API) do
      post "/images", request: upload_schema
      def upload; end
    end

    content = RailsNinja::OpenAPI::Generator.new(api).to_hash[:paths]["/images"]["post"][:requestBody][:content]
    assert_equal ["multipart/form-data"], content.keys

    nested_schema = Class.new(RailsNinja::Schema::Base) { field :inner, upload_schema }
    nested_schema.define_singleton_method(:name) { "NestedIn" }
    nested_api = Class.new(RailsNinja::API) do
      post "/nested", request: nested_schema
      def upload; end
    end

    error = assert_raises(RailsNinja::Error) { RailsNinja::OpenAPI::Generator.new(nested_api).to_hash }
    assert_match(/top level.*inner/, error.message)
  end

  def test_recursive_request_schema_generates
    node = Class.new(RailsNinja::Schema::Base) { field :name, RailsNinja::Types::String }
    node.define_singleton_method(:name) { "Node" }
    node.field :children, [node], required: false
    api = Class.new(RailsNinja::API) do
      post "/nodes", request: node
      def create; end
    end

    spec = RailsNinja::OpenAPI::Generator.new(api).to_hash

    assert_equal ["application/json"], spec[:paths]["/nodes"]["post"][:requestBody][:content].keys
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
