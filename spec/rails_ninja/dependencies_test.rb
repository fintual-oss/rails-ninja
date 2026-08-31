# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"

class DependenciesTest < Minitest::Test
  def test_action_pack_and_active_support_versions_match
    assert_equal ActionPack::VERSION::STRING, ActiveSupport::VERSION::STRING
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
