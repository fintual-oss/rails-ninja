# frozen_string_literal: true

module RailsNinja
  module Schema
    class OneOf
      attr_reader :variants, :discriminator

      def initialize(variants, discriminator: nil)
        @variants = variants
        @discriminator = discriminator
      end
    end
  end
end
