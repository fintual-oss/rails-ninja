# frozen_string_literal: true

module RailsNinja
  module Schema
    Field = Struct.new(:name, :type, :required, :default, :enum, keyword_init: true) do
      def initialize(name:, type:, required: true, default: nil, enum: nil)
        super
      end
    end
  end
end
