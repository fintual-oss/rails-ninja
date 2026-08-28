# frozen_string_literal: true

module RailsNinja
  class API < EndpointGroup
    FORM_MEDIA_TYPES = %w[application/x-www-form-urlencoded multipart/form-data].freeze

    abstract!
    include ActionController::Instrumentation

    # --- Class-level DSL ---

    class << self
      # Config DSL
      def title(value = nil)
        if value
          @_title = value
        else
          @_title
        end
      end

      def _title
        @_title
      end

      def version(value = nil)
        if value
          @_version = value
        else
          @_version
        end
      end

      def _version
        @_version
      end

      def server(value = nil)
        if value
          @_server = value
        else
          @_server
        end
      end

      def _server
        @_server
      end

      def docs(enabled = nil)
        if enabled.nil?
          @_docs_enabled
        else
          @_docs_enabled = enabled
        end
      end

      def _docs_enabled?
        return @_docs_enabled unless @_docs_enabled.nil?

        true
      end

      def openapi_security_scheme(name, **options)
        _openapi_security_schemes[name.to_s] = options
      end

      def _openapi_security_schemes
        @_openapi_security_schemes ||= {}
      end

      def openapi_security(*names)
        if names.any?
          @_openapi_security = names.flatten.map(&:to_s)
        else
          @_openapi_security
        end
      end

      def _openapi_security
        @_openapi_security || []
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_openapi_security_schemes, _openapi_security_schemes.transform_values(&:dup))
        subclass.instance_variable_set(:@_openapi_security, _openapi_security.dup)
        RailsNinja.registered_apis << subclass
      end

      # Rack interface — makes this class usable with Rack::Test and as a Rack app
      def call(env)
        path = env["PATH_INFO"] || "/"
        verb = env["REQUEST_METHOD"]

        if _docs_enabled?
          return Response.html(Swagger::UI.html(spec_url: "./openapi.json")) if verb == "GET" && path == "/docs"
          return Response.json(OpenAPI::Generator.new(self).to_hash) if verb == "GET" && path == "/openapi.json"
        end

        match = _match_route(verb, path)
        return Response.error("Not Found", status: 404) unless match

        endpoint, full_path, dispatch_name, _regex, mount_path = match
        path_params = _extract_path_params(full_path, path)
        env["action_dispatch.request.path_parameters"] = path_params.merge(
          controller: controller_path || "rails_ninja",
          action: dispatch_name.to_s
        )
        env["rails_ninja.endpoint"] = endpoint
        env["rails_ninja.mount_path"] = mount_path

        req = ActionDispatch::Request.new(env)
        res = make_response!(req)
        dispatch(dispatch_name.to_s, req, res)
      end

      def _match_route(verb, path)
        _cached_dispatch_table.find do |_ep, _full_path, _dispatch_name, regex|
          _ep.verb.to_s.upcase == verb.upcase && regex.match?(path)
        end
      end

      def _cached_dispatch_table
        @_cached_dispatch_table ||= _dispatch_table
      end

      def _extract_path_params(full_path, actual_path)
        regex = _path_to_regex(full_path)
        match = regex.match(actual_path)
        match ? match.named_captures.transform_keys(&:to_sym) : {}
      end

      # Builds a flat dispatch table: [operation, full_path, dispatch_name, regex, mount_path]
      # For the API's own endpoints, dispatch_name == handler.
      # For endpoints of mounted groups, dispatch_name is the unique method defined on the API.
      # mount_path is the branch of group classes leading to the operation — the same operation
      # object can appear on several branches when a group is mounted more than once.
      def _dispatch_table(group_class = self, prefix = "/", mount_path = nil)
        mount_path ||= [group_class]
        results = []

        group_class._endpoints.each do |endpoint|
          full_path = normalize_route_path("#{prefix}/#{endpoint.path}")
          regex = _path_to_regex(full_path)
          dispatch_name = if group_class == self
                            endpoint.handler
                          else
                            _unique_handler_name(endpoint.api_class, endpoint.display_handler)
                          end
          results << [endpoint, full_path, dispatch_name, regex, mount_path]
        end

        group_class._mounted_groups.each do |mounted|
          sub_prefix = normalize_route_path("#{prefix}/#{mounted[:prefix]}")
          results.concat(_dispatch_table(mounted[:group_class], sub_prefix, mount_path + [mounted[:group_class]]))
        end

        results
      end

      def _path_to_regex(path)
        pattern = "^" + path.gsub(/:(\w+)/, '(?<\1>[^/]+)') + "$"
        Regexp.new(pattern)
      end

      # Draw Rails routes for all endpoints in this API (including mounted groups)
      def draw_routes(router_context, prefix: "/")
        register_as_controller!

        _dispatch_table(self, prefix).each do |endpoint, full_path, dispatch_name, _regex|
          router_context.match full_path,
                               to: "#{controller_path}##{dispatch_name}",
                               via: endpoint.verb
        end

        draw_docs_routes(router_context, prefix) if _docs_enabled?
      end

      # Register this class so Rails can find it via controller_path + "Controller"
      def register_as_controller!
        return if @_registered_as_controller

        # Rails looks up "controller_path_controller".camelize, so we register an alias
        controller_class_name = "#{name}Controller"
        parts = controller_class_name.split("::")
        const_name = parts.pop
        namespace = parts.empty? ? Object : parts.join("::").constantize
        namespace.const_set(const_name, self) unless namespace.const_defined?(const_name, false)
        @_registered_as_controller = true
      end

      private

      def draw_docs_routes(router_context, prefix)
        api_class = self
        docs_path = normalize_route_path("#{prefix}/docs")
        openapi_path = normalize_route_path("#{prefix}/openapi.json")

        router_context.match docs_path, to: ->(_env) {
          body = Swagger::UI.html(spec_url: "./openapi.json")
          [200, { "content-type" => "text/html" }, [body]]
        }, via: :get

        router_context.match openapi_path, to: ->(_env) {
          generator = OpenAPI::Generator.new(api_class)
          [200, { "content-type" => "application/json" }, [generator.to_json]]
        }, via: :get
      end

      def normalize_route_path(path)
        "/" + path.squeeze("/").gsub(%r{^/|/$}, "")
      end
    end

    # Let Instrumentation wrap this so "Processing"/"Completed" logs appear
    def process_action(action_name, *args)
      @_ninja_endpoint, @_ninja_mount_path = find_route(action_name)

      unless @_ninja_endpoint
        head(:not_found)
        return
      end

      super
    rescue ValidationError => e
      self.status = 422
      self.content_type = "application/json"
      self.response_body = [MultiJson.dump({ errors: e.errors })]
    rescue NotFoundError => e
      self.status = 404
      self.content_type = "application/json"
      self.response_body = [MultiJson.dump({ error: e.message })]
    end

    # Override send_action (called by AbstractController::Base#process_action via super chain)
    # to inject before_actions, validation, and result rendering
    def send_action(action_name)
      endpoint = @_ninja_endpoint

      @_ninja_handler_instance = build_group_instance(endpoint.api_class) unless endpoint.api_class == self.class
      run_ancestor_before_actions(endpoint)
      unless performed?
        run_before_actions(endpoint)
      end
      unless performed?
        validate_request!(endpoint)
      end
      unless performed?
        result = super
        render_result(result, endpoint) unless performed?
      end
    end

    private

    def find_route(action_name)
      # When dispatched via API.call, the exact route is stored in the env
      stored = request.env["rails_ninja.endpoint"]
      return [stored, request.env["rails_ninja.mount_path"]] if stored

      # When dispatched via Rails routes, match by the dispatch method name
      action_sym = action_name.to_sym
      rows = self.class._cached_dispatch_table.select do |_op, _path, dispatch_name, _regex, _mount_path|
        dispatch_name == action_sym
      end
      row = rows.one? ? rows.first : disambiguate_row(rows)
      return [nil, nil] unless row

      [row[0], row[4]]
    end

    # A dispatch name can map to several table rows (a group mounted more than
    # once, or deprecated path aliases); pick the row whose path matches the
    # Rails route that dispatched this request.
    def disambiguate_row(rows)
      pattern = request.respond_to?(:route_uri_pattern) && request.route_uri_pattern&.delete_suffix("(.:format)")
      return rows.first unless pattern

      rows.select { |_op, full_path, _dispatch_name, _regex, _mount_path| pattern.end_with?(full_path) }
        .max_by { |_op, full_path, _dispatch_name, _regex, _mount_path| full_path.length } || rows.first
    end

    def run_ancestor_before_actions(endpoint)
      groups = @_ninja_mount_path || [self.class]
      groups.each do |group|
        next if group == endpoint.api_class
        next if group._before_actions.empty?

        break if run_actions_list(group._before_actions, build_group_instance(group))
      end
    end

    def run_before_actions(endpoint)
      if endpoint.api_class == self.class
        run_actions_list(endpoint.api_class._before_actions)
      else
        run_actions_list(endpoint.api_class._before_actions, @_ninja_handler_instance)
      end
    end

    def build_group_instance(group)
      instance = group.new
      instance.set_request!(request)
      instance.set_response!(response)
      instance
    end

    def run_actions_list(actions, group_instance = nil)
      actions.each do |action|
        if group_instance && action.is_a?(Symbol)
          group_instance.public_send(action)

          if group_instance.performed?
            self.status = group_instance.status
            self.content_type = group_instance.content_type
            self.response_body = group_instance.response_body
          end
        elsif action.is_a?(Symbol)
          public_send(action)
        else
          instance_exec(&action)
        end

        break if performed?
      end

      performed?
    end

    def validate_request!(endpoint)
      return unless endpoint.request_schema

      input = request_input(endpoint.request_schema)
      validated, errors = endpoint.request_schema.validate(input)

      if errors.empty?
        params.merge!(validated)
        return
      end

      self.status = 422
      self.content_type = "application/json"
      self.response_body = [MultiJson.dump({ errors: errors })]
    end

    def request_input(schema_class)
      path = decode_parameters(schema_class, request.path_parameters)
      query = decode_parameters(schema_class, request.query_parameters)
      body = if FORM_MEDIA_TYPES.include?(request.media_type)
               decode_parameters(schema_class, request.request_parameters)
             else
               request.request_parameters.deep_symbolize_keys
             end

      path.merge(query).merge(body)
    end

    def decode_parameters(schema_class, parameters)
      Schema::ParameterDecoder.new(schema_class, parameters).call
    end

    def render_result(result, endpoint)
      if result.is_a?(Array) && result.length == 3 && result[0].is_a?(Integer)
        self.status = result[0]
        result[1].each { |k, v| headers[k] = v }
        self.response_body = result[2]
      elsif result.is_a?(Integer) && result.between?(100, 599)
        head result
      elsif endpoint.response_schema
        body = if endpoint.response_is_array?
                 endpoint.response_schema.first.serialize_many(result)
               else
                 endpoint.response_schema.serialize(result)
               end
        self.status = 200
        self.content_type = "application/json"
        self.response_body = [MultiJson.dump(body)]
      else
        # Nothing was rendered explicitly and no response schema is declared:
        # return an empty body instead of serializing whatever the handler
        # happened to return (e.g. a job object from perform_later).
        self.status = 200
        self.response_body = []
      end
    end
  end
end
