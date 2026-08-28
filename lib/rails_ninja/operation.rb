# frozen_string_literal: true

module RailsNinja
  class Operation
    attr_reader :verb, :path, :handler, :display_handler, :api_class,
                :request_schema, :responses_map, :tags, :summary, :header_params

    def initialize(verb:, path:, handler:, api_class:, request: nil, response: nil, responses: nil,
      tags: nil, summary: nil, headers: nil, deprecated: false)
      @verb = verb
      @path = path
      @handler = handler
      @display_handler = handler
      @api_class = api_class
      @request_schema = request
      @responses_map = responses || (response ? { 200 => response } : {})
      @tags = tags || api_class._tags || []
      @summary = summary || handler.to_s.tr("_", " ").capitalize
      @header_params = merge_headers(api_class._headers, headers)
      @deprecated = deprecated
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
          { name: h[:name], required: h.fetch(:required, true), schema: { type: h.fetch(:type, "string") } }
        end
      end
    end
  end
end
