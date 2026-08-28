# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class EndpointGroupTest < Minitest::Test
  include Rack::Test::Methods

  # Delegate at call time so a test can switch @current_app between requests
  # (rack-test caches the app when the session is first built).
  def app
    ->(env) { @current_app.call(env) }
  end

  def test_group_registers_endpoints_with_verb_dsl
    group = Class.new(RailsNinja::EndpointGroup) do
      get "/items"
      def list_items; end
    end

    assert_equal 1, group._endpoints.size
    operation = group._endpoints.first
    assert_equal :get, operation.verb
    assert_equal "/items", operation.path
  end

  def test_group_has_no_document_level_dsl
    refute_respond_to RailsNinja::EndpointGroup, :title
    refute_respond_to RailsNinja::EndpointGroup, :version
    refute_respond_to RailsNinja::EndpointGroup, :server
    refute_respond_to RailsNinja::EndpointGroup, :docs
    refute_respond_to RailsNinja::EndpointGroup, :draw_routes
    refute_respond_to RailsNinja::EndpointGroup, :call
  end

  def test_group_tags_apply_to_included_endpoints
    endpoint = Class.new(RailsNinja::Endpoint) do
      get "/items"
      def handle; end
    end

    group = Class.new(RailsNinja::EndpointGroup) do
      tags "Inventory"
    end
    group.include_endpoint(endpoint)

    assert_equal ["Inventory"], group._endpoints.first.tags
  end

  def test_untagged_group_endpoints_stay_untagged
    group = Class.new(RailsNinja::EndpointGroup) do
      get "/items"
      def list_items; end
    end

    assert_empty group._endpoints.first.tags
  end

  def test_mounted_group_endpoints_are_dispatched_through_the_api
    group = Class.new(RailsNinja::EndpointGroup) do
      get "/items"
      def list_items
        render_json([{ id: 1 }])
      end
    end

    api = Class.new(RailsNinja::API) { docs false }
    api.mount group, prefix: "/inventory"
    @current_app = api

    get "/inventory/items"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal 1, body[0][:id]
  end

  def test_nested_groups_are_dispatched_through_the_api
    inner = Class.new(RailsNinja::EndpointGroup) do
      get "/leaf"
      def leaf
        render_json({ from: "inner" })
      end
    end
    outer = Class.new(RailsNinja::EndpointGroup)
    outer.mount inner, prefix: "/inner"

    api = Class.new(RailsNinja::API) { docs false }
    api.mount outer, prefix: "/outer"
    @current_app = api

    get "/outer/inner/leaf"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "inner", body[:from]
  end

  def test_group_can_be_mounted_into_multiple_apis
    group = Class.new(RailsNinja::EndpointGroup) do
      get "/shared"
      def shared
        render_json({ ok: true })
      end
    end

    api1 = Class.new(RailsNinja::API) { docs false }
    api2 = Class.new(RailsNinja::API) { docs false }
    api1.mount group, prefix: "/a"
    api2.mount group, prefix: "/b"

    @current_app = api1
    get "/a/shared"
    assert_equal 200, last_response.status

    @current_app = api2
    get "/b/shared"
    assert_equal 200, last_response.status
  end

  def test_endpoints_can_be_mounted_directly_on_an_api
    endpoint = Class.new(RailsNinja::Endpoint) do
      get "/:id", tags: ["Custom"]
      def show
        render_json({ id: params[:id] })
      end
    end

    api = Class.new(RailsNinja::API)
    api.mount endpoint, prefix: "/records"
    @current_app = api

    get "/records/42"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "42", body[:id]

    get "/openapi.json"
    spec = MultiJson.load(last_response.body)
    assert_equal ["Custom"], spec["paths"]["/records/{id}"]["get"]["tags"]
  end

  def test_openapi_spec_groups_mounted_group_endpoints_under_their_tag
    endpoint = Class.new(RailsNinja::Endpoint) do
      post "/notify"
      def handle; end
    end

    group = Class.new(RailsNinja::EndpointGroup) do
      tags "Notifications"
    end
    group.include_endpoint(endpoint)

    api = Class.new(RailsNinja::API) do
      title "Docs API"
      version "1.0"
    end
    api.mount group, prefix: "/notifications"
    @current_app = api

    get "/openapi.json"

    spec = MultiJson.load(last_response.body)
    assert_equal ["Notifications"], spec["paths"]["/notifications/notify"]["post"]["tags"]
  end

  def test_mounting_an_api_into_a_group_raises
    api = Class.new(RailsNinja::API) { docs false }
    group = Class.new(RailsNinja::EndpointGroup)

    error = assert_raises(RailsNinja::Error) { group.mount api, prefix: "/sub" }
    assert_match(/cannot be mounted/, error.message)
  end

  def test_before_action_state_is_visible_to_the_handler
    group = Class.new(RailsNinja::EndpointGroup) do
      before_action :load_user

      define_method(:load_user) do
        @user = "benja"
      end

      get "/me"
      def me
        render_json({ user: @user })
      end
    end

    api = Class.new(RailsNinja::API) { docs false }
    api.mount group, prefix: "/sub"
    @current_app = api

    get "/sub/me"

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "benja", body[:user]
  end

  def test_sibling_group_before_actions_do_not_run_for_other_groups
    locked = Class.new(RailsNinja::EndpointGroup) do
      before_action :deny

      define_method(:deny) do
        head :forbidden
      end

      get "/data"
      def locked_data
        render_json({ ok: true })
      end
    end
    open = Class.new(RailsNinja::EndpointGroup) do
      get "/data"
      def open_data
        render_json({ ok: true })
      end
    end

    api = Class.new(RailsNinja::API) { docs false }
    api.mount locked, prefix: "/locked"
    api.mount open, prefix: "/open"
    @current_app = api

    get "/open/data"
    assert_equal 200, last_response.status

    get "/locked/data"
    assert_equal 403, last_response.status
  end

  def test_nested_group_endpoints_run_only_their_own_branch_before_actions
    inner = Class.new(RailsNinja::EndpointGroup) do
      get "/leaf"
      def leaf
        render_json({ ok: true })
      end
    end
    outer = Class.new(RailsNinja::EndpointGroup) do
      before_action :check_outer

      define_method(:check_outer) do
        head :forbidden unless request.headers["X-Outer"] == "yes"
      end
    end
    outer.mount inner, prefix: "/inner"

    sibling = Class.new(RailsNinja::EndpointGroup) do
      before_action :always_deny

      define_method(:always_deny) do
        head :forbidden
      end
    end

    api = Class.new(RailsNinja::API) { docs false }
    api.mount outer, prefix: "/outer"
    api.mount sibling, prefix: "/sibling"
    @current_app = api

    # The sibling's callback must not leak into the outer/inner branch,
    # while outer's own callback still guards its nested endpoints.
    get "/outer/inner/leaf"
    assert_equal 403, last_response.status

    get "/outer/inner/leaf", {}, { "HTTP_X_OUTER" => "yes" }
    assert_equal 200, last_response.status
  end

  def test_group_mounted_twice_runs_the_matched_branch_before_actions
    shared = Class.new(RailsNinja::EndpointGroup) do
      get "/data"
      def data
        render_json({ ok: true })
      end
    end
    open_parent = Class.new(RailsNinja::EndpointGroup)
    open_parent.mount shared, prefix: "/x"
    secured_parent = Class.new(RailsNinja::EndpointGroup) do
      before_action :authenticate!

      define_method(:authenticate!) do
        head :unauthorized unless request.headers["X-Token"] == "valid"
      end
    end
    secured_parent.mount shared, prefix: "/x"

    api = Class.new(RailsNinja::API) { docs false }
    api.mount open_parent, prefix: "/open"
    api.mount secured_parent, prefix: "/secure"
    @current_app = api

    get "/open/x/data"
    assert_equal 200, last_response.status

    get "/secure/x/data"
    assert_equal 401, last_response.status

    get "/secure/x/data", {}, { "HTTP_X_TOKEN" => "valid" }
    assert_equal 200, last_response.status
  end

  def test_group_before_actions_run_for_its_own_endpoints
    group = Class.new(RailsNinja::EndpointGroup) do
      before_action :check_role

      define_method(:check_role) do
        head :forbidden unless request.headers["X-Role"] == "admin"
      end

      get "/secret"
      def secret
        render_json({ secret: true })
      end
    end

    api = Class.new(RailsNinja::API) { docs false }
    api.mount group, prefix: "/sub"
    @current_app = api

    get "/sub/secret"
    assert_equal 403, last_response.status

    get "/sub/secret", {}, { "HTTP_X_ROLE" => "admin" }
    assert_equal 200, last_response.status
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
