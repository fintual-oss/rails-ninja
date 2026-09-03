# frozen_string_literal: true

namespace :rails_ninja do
  namespace :openapi do
    desc "Generate OpenAPI JSON spec files for all registered APIs"
    task generate: :environment do
      output = ENV.fetch("OUTPUT", "public/openapi")
      openapi_version = ENV.fetch("OPENAPI_VERSION", RailsNinja::OpenAPI::Generator::DEFAULT_VERSION)
      RailsNinja.generate_openapi(output: output, openapi_version: openapi_version)
      puts "Generated OpenAPI #{openapi_version} specs in #{output}/"
    end
  end
end
