# frozen_string_literal: true

module RailsNinja
  class Error < StandardError; end

  class ValidationError < Error
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("Validation failed: #{errors.join(', ')}")
    end
  end

  class NotFoundError < Error
    def initialize(msg = "Not Found")
      super
    end
  end
end
