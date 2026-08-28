# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"
require "tmpdir"
require "fileutils"
require "rake"

# Test APIs for generation
class PublicApi < RailsNinja::API
  title "Public API"
  version "1.0"

  schema :Widget do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
  end

  get "/widgets", response: [Widget]
  def list_widgets; end
end

class AdminApi < RailsNinja::API
  title "Admin API"
  version "2.0"

  get "/users"
  def list_users; end
end

class GenerateOpenAPITest < Minitest::Test
  def setup
    @original_apis = RailsNinja.registered_apis.dup
  end

  def teardown
    RailsNinja.instance_variable_set(:@registered_apis, @original_apis)
  end

  def test_generates_files_for_all_registered_apis
    Dir.mktmpdir do |dir|
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi, AdminApi])
      RailsNinja.generate_openapi(output: dir)

      assert File.exist?(File.join(dir, "public_api.json")), "Expected public_api.json to exist"
      assert File.exist?(File.join(dir, "admin_api.json")), "Expected admin_api.json to exist"
    end
  end

  def test_file_contents_are_valid_openapi
    Dir.mktmpdir do |dir|
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi])
      RailsNinja.generate_openapi(output: dir)

      spec = MultiJson.load(File.read(File.join(dir, "public_api.json")))
      assert_equal "3.2.0", spec["openapi"]
      assert_equal "Public API", spec["info"]["title"]
      assert spec["paths"]
    end
  end

  def test_file_naming_is_snake_cased
    Dir.mktmpdir do |dir|
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi, AdminApi])
      RailsNinja.generate_openapi(output: dir)

      files = Dir.children(dir).sort
      assert_includes files, "public_api.json"
      assert_includes files, "admin_api.json"
    end
  end

  def test_custom_output_directory
    Dir.mktmpdir do |base|
      custom = File.join(base, "custom_specs")
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi])
      RailsNinja.generate_openapi(output: custom)

      assert File.exist?(File.join(custom, "public_api.json"))
    end
  end

  def test_creates_output_directory_if_missing
    Dir.mktmpdir do |base|
      nested = File.join(base, "a", "b", "c")
      refute File.exist?(nested)

      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi])
      RailsNinja.generate_openapi(output: nested)

      assert File.directory?(nested)
      assert File.exist?(File.join(nested, "public_api.json"))
    end
  end

  def test_excludes_action_classes
    # Action subclasses should not appear in registered_apis
    refute RailsNinja.registered_apis.any? { |api| api <= RailsNinja::Endpoint },
           "Action subclasses should not be in registered_apis"
  end

  def test_matches_runtime_spec
    Dir.mktmpdir do |dir|
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi])
      RailsNinja.generate_openapi(output: dir)

      # Get the runtime spec via API.call
      app = PublicApi
      env = Rack::MockRequest.env_for("/openapi.json", method: "GET")
      _, _headers, body = app.call(env)
      runtime_spec = MultiJson.load(body.first)

      generated_spec = MultiJson.load(File.read(File.join(dir, "public_api.json")))

      assert_equal runtime_spec, generated_spec
    end
  end
end

class RakeTaskTest < Minitest::Test
  def setup
    @original_apis = RailsNinja.registered_apis.dup
    @rake = Rake::Application.new
    Rake.application = @rake
    load File.expand_path("../../lib/rails_ninja/tasks.rake", __dir__)
    # Define a no-op :environment task since we're not in Rails
    Rake::Task.define_task(:environment)
  end

  def teardown
    RailsNinja.instance_variable_set(:@registered_apis, @original_apis)
    Rake.application = Rake::Application.new
    ENV.delete("OUTPUT")
  end

  def test_task_is_loadable_and_invokable
    assert Rake::Task.task_defined?("rails_ninja:openapi:generate")

    Dir.mktmpdir do |dir|
      ENV["OUTPUT"] = dir
      RailsNinja.instance_variable_set(:@registered_apis, [PublicApi])
      Rake::Task["rails_ninja:openapi:generate"].invoke

      assert File.exist?(File.join(dir, "public_api.json"))
    end
  end

  def test_respects_output_env_var
    Dir.mktmpdir do |dir|
      custom = File.join(dir, "custom_out")
      ENV["OUTPUT"] = custom
      RailsNinja.instance_variable_set(:@registered_apis, [AdminApi])

      Rake::Task["rails_ninja:openapi:generate"].reenable
      Rake::Task["rails_ninja:openapi:generate"].invoke

      assert File.exist?(File.join(custom, "admin_api.json"))
    end
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
