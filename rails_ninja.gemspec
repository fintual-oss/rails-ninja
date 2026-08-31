# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name = "rails_ninja"
  spec.version = "0.1.0"
  spec.authors = ["Benjamin Urrutia"]
  spec.email = ["benja@fintual.com"]
  spec.summary = "Django Ninja-inspired API framework for Ruby/Rails"
  spec.description = "Define API endpoints with a decorator-like DSL, schema validation, and automatic OpenAPI spec generation."
  spec.homepage = "https://www.fintual.com"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://www.fintual.com"
  spec.metadata["homepage_uri"] = spec.homepage

  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "multi_json", "~> 1.15"
  spec.add_dependency "rack", ">= 2.0"

  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rack-test", ">= 2.0"
  spec.add_development_dependency "rake", ">= 13.0"
end
