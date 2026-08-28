# frozen_string_literal: true

require "action_controller/metal"
require "active_support/core_ext/enumerable"
require "rack"
require "multi_json"

require_relative "rails_ninja/version"
require_relative "rails_ninja/errors"
require_relative "rails_ninja/types/base_scalar"
require_relative "rails_ninja/types/boolean"
require_relative "rails_ninja/types/float"
require_relative "rails_ninja/types/int"
require_relative "rails_ninja/types/string"
require_relative "rails_ninja/schema/field"
require_relative "rails_ninja/schema/one_of"
require_relative "rails_ninja/schema/parameter_decoder"
require_relative "rails_ninja/schema/validator"
require_relative "rails_ninja/schema/serializer"
require_relative "rails_ninja/schema"
require_relative "rails_ninja/operation"
require_relative "rails_ninja/response"
require_relative "rails_ninja/openapi/schema_ref"
require_relative "rails_ninja/openapi/generator"
require_relative "rails_ninja/swagger/ui"
require_relative "rails_ninja/endpoint_group"
require_relative "rails_ninja/api"
require_relative "rails_ninja/endpoint"

require_relative "rails_ninja/railtie" if defined?(Rails::Railtie)

module RailsNinja
  def self.registered_apis
    @registered_apis ||= []
  end

  def self.generate_openapi(output: "public/openapi")
    require "fileutils"
    FileUtils.mkdir_p(output)

    registered_apis.each do |api_class|
      generator = OpenAPI::Generator.new(api_class)

      filename = api_class.name.split("::").last
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase + ".json"

      File.write(File.join(output, filename), generator.to_json)
    end
  end
end
