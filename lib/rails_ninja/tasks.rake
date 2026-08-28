# frozen_string_literal: true

namespace :rails_ninja do
  namespace :openapi do
    desc "Generate OpenAPI JSON spec files for all registered APIs"
    task generate: :environment do
      output = ENV.fetch("OUTPUT", "public/openapi")
      RailsNinja.generate_openapi(output: output)
      puts "Generated OpenAPI specs in #{output}/"
    end
  end
end
