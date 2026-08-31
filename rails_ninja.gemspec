# frozen_string_literal: true

require_relative "lib/rails_ninja/version"

Gem::Specification.new do |spec|
  spec.name = "rails_ninja"
  spec.version = RailsNinja::VERSION
  spec.authors = ["Benjamin Urrutia"]
  spec.email = ["benja@fintual.com"]
  spec.summary = "Django Ninja-inspired API framework for Ruby/Rails"
  spec.description = "Define API endpoints with a decorator-like DSL, schema validation, and automatic OpenAPI spec generation."
  spec.homepage = "https://github.com/fintual-oss/rails-ninja"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*"].select { |path| File.file?(path) } +
      %w[LICENSE README.md rails_ninja.gemspec]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "multi_json", "~> 1.15"
  spec.add_dependency "rack", ">= 2.0"

  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rack-test", ">= 2.0"
  spec.add_development_dependency "rake", ">= 13.0"
end
