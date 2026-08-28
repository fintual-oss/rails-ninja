# frozen_string_literal: true

module RailsNinja
  module Swagger
    module UI
      module_function

      def html(spec_url: "./openapi.json")
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <title>API Documentation</title>
            <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
            <style>
              body { margin: 0; padding: 0; }
            </style>
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script>
              SwaggerUIBundle({
                url: "#{spec_url}",
                dom_id: '#swagger-ui',
                presets: [SwaggerUIBundle.presets.apis],
                layout: "BaseLayout"
              })
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
