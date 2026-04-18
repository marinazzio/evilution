# frozen_string_literal: true

require_relative "../suggestion"

# rubocop:disable Style/OneClassPerFile
module Evilution::Reporter::Suggestion::Templates
end

class Evilution::Reporter::Suggestion::Registry
  # rubocop:enable Style/OneClassPerFile
  def self.default
    return @default if @default

    require_relative "templates/generic"
    require_relative "templates/rspec"
    require_relative "templates/minitest"

    registry = new
    Evilution::Reporter::Suggestion::Templates::Generic::GENERIC_ENTRIES.each do |op, text|
      registry.register_generic(op, text)
    end
    Evilution::Reporter::Suggestion::Templates::Rspec::RSPEC_ENTRIES.each do |op, blk|
      registry.register_concrete(op, integration: :rspec, block: blk)
    end
    Evilution::Reporter::Suggestion::Templates::Minitest::MINITEST_ENTRIES.each do |op, blk|
      registry.register_concrete(op, integration: :minitest, block: blk)
    end

    @default = registry
  end

  def self.reset!
    @default = nil
  end

  def initialize
    @generic = {}
    @concrete = Hash.new { |h, k| h[k] = {} }
  end

  def register_generic(operator_name, text)
    @generic[operator_name] = text
    self
  end

  def register_concrete(operator_name, integration:, block:)
    @concrete[integration][operator_name] = block
    self
  end

  def generic(operator_name)
    @generic[operator_name]
  end

  def concrete(operator_name, integration:)
    @concrete.fetch(integration, {})[operator_name]
  end

  def each_generic_operator(&)
    return @generic.each_key unless block_given?

    @generic.each_key(&)
  end
end
