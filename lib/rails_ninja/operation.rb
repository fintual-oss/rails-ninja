# frozen_string_literal: true

module RailsNinja
  class Operation
    attr_reader :verb, :path, :handler, :display_handler, :api_class,
                :request_schema, :responses_map, :tags, :summary, :header_params,
                :description, :operation_id, :path_params, :request_description, :response_documentation

    def initialize(verb:, path:, handler:, api_class:, request: nil, response: nil, responses: nil,
      tags: nil, summary: nil, headers: nil, deprecated: false, description: nil,
      operation_id: nil, path_params: {}, request_description: nil)
      @verb = verb
      @path = path
      @handler = handler
      @display_handler = handler
      @api_class = api_class
      @request_schema = request
      @response_documentation = {}
      @responses_map = (responses || (response ? { 200 => response } : {})).to_h do |status, declaration|
        if declaration.is_a?(Hash)
          unknown = declaration.keys - %i[schema description example examples headers]
          raise ArgumentError, "Unsupported response #{status} keys: #{unknown.join(', ')}" if unknown.any?
          if declaration.key?(:example) && declaration.key?(:examples)
            raise ArgumentError, "Response #{status} cannot declare both example and examples"
          end
          @response_documentation[status] = declaration.except(:schema).deep_dup
          [status, declaration.fetch(:schema)]
        else
          [status, declaration]
        end
      end
      @tags = tags || api_class._tags || []
      @summary = summary || handler.to_s.tr("_", " ").capitalize
      @header_params = merge_headers(api_class._headers, headers)
      @deprecated = deprecated
      @description = description
      @operation_id = operation_id
      @path_params = path_params.transform_keys(&:to_s).deep_dup
      @path_params.each_value do |metadata|
        unknown = metadata.keys - %i[description example schema]
        raise ArgumentError, "Unsupported path parameter keys: #{unknown.join(', ')}" if unknown.any?
      end
      @request_description = request_description
    end

    def deprecated?
      @deprecated
    end

    def response_schema
      responses_map[200]
    end

    def with_handler(new_handler)
      @handler = new_handler
      self
    end

    def with_tags(new_tags)
      @tags = new_tags
      self
    end

    def response_is_array?
      response_schema.is_a?(Array)
    end

    def response_schema_class
      response_is_array? ? response_schema.first : response_schema
    end

    private

    def merge_headers(class_headers, endpoint_headers)
      parsed_class = parse_headers(class_headers)
      parsed_endpoint = parse_headers(endpoint_headers)

      # Endpoint-level headers override class-level headers with the same name
      merged = parsed_class.reject { |ch| parsed_endpoint.any? { |eh| eh[:name] == ch[:name] } }
      merged + parsed_endpoint
    end

    def parse_headers(headers)
      return [] if headers.nil?

      Array(headers).filter_map do |h|
        if h.is_a?(String)
          { name: h, required: true, schema: { type: "string" } }
        elsif h.is_a?(Hash)
          { name: h[:name], required: h.fetch(:required, true),
            schema: h.fetch(:schema, { type: h.fetch(:type, "string") }) }
            .merge(h.slice(:description, :example)).deep_dup
        end
      end
    end
  end
end
