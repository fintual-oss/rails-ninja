# frozen_string_literal: true

module RailsNinja
  module OpenAPI
    class Generator
      DEFAULT_VERSION = "3.2.0"
      SUPPORTED_VERSION_PATTERN = /\A3\.(?:0|1|2)\.\d+\z/

      def initialize(api_class, openapi_version: DEFAULT_VERSION)
        unless openapi_version.match?(SUPPORTED_VERSION_PATTERN)
          raise ArgumentError, "unsupported OpenAPI version: #{openapi_version.inspect} (expected 3.0.x, 3.1.x, or 3.2.x)"
        end

        @api_class = api_class
        @openapi_version = openapi_version
      end

      def to_hash
        @schema_names = build_schema_names

        components = { schemas: build_schemas }
        if @api_class._openapi_security_schemes.any?
          components[:securitySchemes] = @api_class._openapi_security_schemes
        end

        spec = {
          openapi: @openapi_version,
          info: {
            title: @api_class._title || @api_class.name || "API",
            version: @api_class._version || "0.1.0",
          },
          paths: build_paths,
          components: components,
        }
        spec[:servers] = [{ url: @api_class._server }] if @api_class._server
        if @api_class._openapi_security.any?
          spec[:security] = @api_class._openapi_security.map { |name| { name => [] } }
        end
        spec
      end

      def to_json(*_args)
        MultiJson.dump(to_hash)
      end

      private

      def collect_routes(group_class = @api_class, prefix = "/")
        routes = []

        group_class._endpoints.each do |endpoint|
          full_path = normalize_path("#{prefix}/#{endpoint.path}")
          routes << { endpoint: endpoint, full_path: full_path }
        end

        group_class._mounted_groups.each do |mounted|
          sub_prefix = normalize_path("#{prefix}/#{mounted[:prefix]}")
          routes.concat(collect_routes(mounted[:group_class], sub_prefix))
        end

        routes
      end

      def normalize_path(path)
        "/" + path.squeeze("/").gsub(%r{^/|/$}, "")
      end

      def build_paths
        routes = collect_routes
        grouped = routes.group_by { |r| r[:full_path] }

        grouped.each_with_object({}) do |(path, path_routes), paths|
          openapi_path = path.gsub(/:(\w+)/, '{\1}')
          paths[openapi_path] = {}

          path_routes.each do |route|
            endpoint = route[:endpoint]
            verb = endpoint.verb.to_s.downcase
            body_verb = %w[get delete head].exclude?(verb)

            operation = { summary: endpoint.summary }
            operation[:tags] = endpoint.tags if endpoint.tags&.any?
            operation[:responses] = build_responses(endpoint)
            # Deprecated aliases share a handler with the primary endpoint; only the
            # current path carries the operationId to keep it unique across the spec.
            operation[:operationId] = build_operation_id(endpoint) unless endpoint.deprecated?
            operation[:deprecated] = true if endpoint.deprecated?

            if endpoint.request_schema && body_verb
              operation[:requestBody] = build_request_body(endpoint.request_schema)
            end

            params = extract_path_params(path) + extract_header_params(endpoint)
            params += extract_query_params(endpoint) unless body_verb
            operation[:parameters] = params if params.any?

            paths[openapi_path][verb] = operation
          end
        end
      end

      def build_responses(endpoint)
        return { "200" => { description: "Successful response" } } if endpoint.responses_map.empty?

        endpoint.responses_map.each_with_object({}) do |(status, schema), out|
          schema_node = if schema.is_a?(Array)
                          { type: "array", items: schema_ref(schema.first) }
                        else
                          schema_ref(schema)
                        end

          out[status.to_s] = {
            description: response_description_for(status),
            content: { "application/json" => { schema: schema_node } },
          }
        end
      end

      def response_description_for(status)
        case status.to_i
        when 200..299 then "Successful response"
        when 400 then "Bad request"
        when 401 then "Unauthorized"
        when 403 then "Forbidden"
        when 404 then "Not found"
        when 409 then "Conflict"
        when 422 then "Unprocessable entity"
        when 429 then "Too many requests"
        when 500..599 then "Server error"
        else "Response"
        end
      end

      def build_request_body(schema)
        {
          required: true,
          content: {
            "application/json" => {
              schema: schema_ref(schema),
            },
          },
        }
      end

      def schema_ref(type)
        if type.is_a?(Schema::OneOf)
          result = { "oneOf" => type.variants.map { |v| schema_ref(v) } }
          if type.discriminator
            result["discriminator"] = {
              "propertyName" => type.discriminator.to_s,
              "mapping" => discriminator_mapping(type),
            }
          end
          result
        elsif type.is_a?(Array)
          { type: "array", items: schema_ref(type.first) }
        elsif type <= Schema::Base
          { "$ref" => "#/components/schemas/#{schema_name(type)}" }
        else
          SchemaRef.primitive_type(type)
        end
      end

      def discriminator_mapping(one_of)
        one_of.variants.each_with_object({}) do |variant, mapping|
          field = variant._fields[one_of.discriminator]
          next unless field&.default

          mapping[field.default.to_s] = "#/components/schemas/#{schema_name(variant)}"
        end
      end

      def extract_path_params(path)
        path.scan(/:(\w+)/).flatten.map do |param|
          { name: param, in: "path", required: true, schema: { type: "string" } }
        end
      end

      def extract_query_params(endpoint)
        return [] unless endpoint.request_schema

        endpoint.request_schema._fields.map do |name, field|
          { name: name.to_s, in: "query", required: field.required, schema: schema_ref(field.type) }
        end
      end

      def extract_header_params(endpoint)
        return [] unless endpoint.header_params&.any?

        endpoint.header_params.map do |h|
          { name: h[:name], in: "header", required: h[:required], schema: h[:schema] }
        end
      end

      def build_operation_id(endpoint)
        tag = endpoint.tags&.first
        handler = endpoint.display_handler.to_s

        if tag
          prefix = tag
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
          "#{prefix}_#{handler}"
        else
          handler
        end
      end

      def schema_name(schema_class)
        @schema_names[schema_class] || schema_class.name || schema_class.object_id.to_s
      end

      def build_schema_names
        names = {}

        collect_schema_sources.each do |api_class|
          api_class._schemas.each do |short_name, schema_class|
            name = short_name.to_s

            next if names.key?(schema_class)

            existing = names.values.find { |n| n == name }
            if existing
              raise Error, "Schema name clash: '#{name}' is defined in multiple API classes"
            end

            names[schema_class] = name
          end
        end

        names
      end

      def build_schemas
        collect_schemas.to_h do |schema_class|
          [schema_name(schema_class), json_schema_for(schema_class)]
        end
      end

      def json_schema_for(schema_class)
        properties = {}
        required = []

        schema_class._fields.each do |name, field|
          property = schema_ref(field.type)
          property[:title] = schema_title(name)
          property[:enum] = field.enum if field.enum
          properties[name.to_s] = property
          required << name.to_s if field.required
        end

        result = { type: "object", title: schema_name(schema_class), properties: properties }
        result[:required] = required if required.any?
        result
      end

      def schema_title(name)
        name.to_s.split("_").map(&:capitalize).join(" ")
      end

      def collect_schemas
        schemas = Set.new

        collect_routes.each do |route|
          endpoint = route[:endpoint]
          walk_schema_tree(endpoint.request_schema, schemas) if endpoint.request_schema
          endpoint.responses_map.each_value { |schema| walk_schema_tree(schema, schemas) }
        end

        schemas
      end

      def walk_schema_tree(type, schemas)
        if type.is_a?(Schema::OneOf)
          type.variants.each { |v| walk_schema_tree(v, schemas) }
        elsif type.is_a?(Array)
          walk_schema_tree(type.first, schemas)
        elsif type.is_a?(Class) && type <= Schema::Base
          return if schemas.include?(type)

          schemas << type
          type._fields.each_value { |field| walk_schema_tree(field.type, schemas) }
        end
      end

      def collect_schema_sources
        sources = Set.new

        collect_routes.each do |route|
          sources << route[:endpoint].api_class
        end

        sources
      end
    end
  end
end
