# frozen_string_literal: true

module RailsNinja
  class Railtie < ::Rails::Railtie
    initializer "rails_ninja.add_autoload_paths" do |app|
      api_path = Rails.root.join("app/api")
      if api_path.exist?
        app.config.autoload_paths << api_path.to_s
        app.config.eager_load_paths << api_path.to_s
      end
    end

    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end
  end
end
