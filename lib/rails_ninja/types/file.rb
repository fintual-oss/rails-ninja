# frozen_string_literal: true

module RailsNinja
  module Types
    class File < BaseScalar
      class << self
        def ruby_classes
          [ActionDispatch::Http::UploadedFile]
        end

        def openapi_schema
          { type: "string", format: "binary" }
        end
      end
    end
  end
end
