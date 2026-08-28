# frozen_string_literal: true

module RailsNinja
  class EndpointGroup < ActionController::Metal
    abstract!

    def params
      @params ||= begin
        raw = request.path_parameters.merge(request.query_parameters).merge(request.request_parameters)
        raw.deep_symbolize_keys
      end
    end

    # --- Class-level DSL ---

    class << self
      # HTTP verb decorators
      %i[get post put patch delete].each do |verb|
        define_method(verb) do |path, **options|
          self._pending_route = { verb: verb, path: path, **options }
        end
      end

      # Schema definition DSL
      def schema(name, &block)
        klass = Class.new(Schema::Base)
        klass.class_eval(&block)

        # Register as a constant on this class so it's accessible by name
        const_set(name, klass)
        _schemas[name] = klass
        klass
      end

      def ninja_headers(*args)
        if args.any?
          @_headers = args.flatten
        else
          @_headers
        end
      end

      def _headers
        @_headers || []
      end

      def before_action(method_name = nil, &block)
        _before_actions << (method_name || block)
      end

      def _before_actions
        @_before_actions ||= []
      end

      def tags(*args)
        if args.any?
          @_tags = args.flatten
        else
          @_tags
        end
      end

      def _tags
        @_tags
      end

      # Pull in endpoints from an Endpoint class
      def include_endpoint(endpoint_class)
        endpoint_class._endpoints.each do |op|
          # Dup the operation so we don't mutate the Endpoint's own copy
          local_op = op.dup
          local_op.with_tags(_tags) if _tags

          # Generate a unique dispatch name to avoid collisions when multiple endpoints share handler names
          original_handler = local_op.display_handler
          dispatch_name = _unique_handler_name(endpoint_class, original_handler)
          local_op.with_handler(dispatch_name)

          _endpoints << local_op

          define_method(dispatch_name) do
            endpoint_instance = @_ninja_handler_instance
            result = endpoint_instance.public_send(original_handler)
            if endpoint_instance.performed?
              self.status = endpoint_instance.status
              self.content_type = endpoint_instance.content_type
              self.response_body = endpoint_instance.response_body
            else
              result
            end
            result
          end
        end
      end

      # Mount an EndpointGroup (or a single Endpoint) under a path prefix
      def mount(group_class, prefix: "/")
        if group_class.is_a?(Class) && group_class <= RailsNinja::API
          raise Error,
                "#{group_class.name || group_class.inspect} is a RailsNinja::API and cannot be mounted: " \
                "an API is a standalone document (one API class per openapi.json). " \
                "Group its endpoints in a RailsNinja::EndpointGroup and mount that instead."
        end

        unless group_class.is_a?(Class) && group_class <= RailsNinja::EndpointGroup
          raise Error,
                "mount expects a RailsNinja::EndpointGroup (or RailsNinja::Endpoint) class, got #{group_class.inspect}"
        end

        _mounted_groups << { group_class: group_class, prefix: prefix }

        # Define dispatch methods for all endpoints in the mounted group tree
        group_class._all_endpoints.each do |op|
          original_handler = op.display_handler
          mounted_class = op.api_class
          dispatch_name = _unique_handler_name(mounted_class, original_handler)

          define_method(dispatch_name) do
            endpoint_instance = @_ninja_handler_instance
            result = endpoint_instance.public_send(original_handler)
            if endpoint_instance.performed?
              self.status = endpoint_instance.status
              self.content_type = endpoint_instance.content_type
              self.response_body = endpoint_instance.response_body
            else
              result
            end
            result
          end
        end
      end

      def _unique_handler_name(source_class, handler)
        # Class names are unique constants, so they disambiguate deterministically
        # across processes (object_id changes per boot, polluting logs and routes).
        # Anonymous classes (e.g. Class.new in tests) have no name, so fall back.
        prefix = source_class.name&.underscore&.tr("/", "_") || "__ninja_#{source_class.object_id}"
        :"#{prefix}__#{handler}"
      end

      # Storage
      def _endpoints
        @_endpoints ||= []
      end

      def _schemas
        @_schemas ||= {}
      end

      def _mounted_groups
        @_mounted_groups ||= []
      end

      def _pending_route
        @_pending_route
      end

      def _pending_route=(route)
        @_pending_route = route
      end

      # The decorator magic: when a method is defined after a verb call,
      # pair them together as an endpoint
      def method_added(method_name)
        super
        return if @_inside_method_added
        return unless _pending_route

        @_inside_method_added = true

        pending = _pending_route
        self._pending_route = nil

        # Extra paths that route to the same handler but are flagged deprecated
        # in the OpenAPI spec. Accepts a single path or an array of paths.
        deprecated_paths = Array(pending.delete(:deprecated_paths))

        route_def = pending.merge(handler: method_name, api_class: self)
        _endpoints << Operation.new(**route_def)

        deprecated_paths.each do |deprecated_path|
          _endpoints << Operation.new(**route_def, path: deprecated_path, deprecated: true)
        end

        @_inside_method_added = false
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_endpoints, [])
        subclass.instance_variable_set(:@_schemas, (_schemas || {}).dup)
        subclass.instance_variable_set(:@_mounted_groups, [])
        subclass.instance_variable_set(:@_before_actions, (_before_actions || []).dup)
      end

      def _all_endpoints
        endpoints = _endpoints.dup
        _mounted_groups.each do |mounted|
          endpoints.concat(mounted[:group_class]._all_endpoints)
        end
        endpoints
      end
    end

    private

    def head(status_code)
      self.status = status_code
      self.content_type = "application/json"
      self.response_body = [MultiJson.dump(nil)]
    end

    def render_json(body, status: 200)
      self.status = status
      self.content_type = "application/json"
      self.response_body = [MultiJson.dump(body)]
    end
  end
end
