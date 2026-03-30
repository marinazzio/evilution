# frozen_string_literal: true

require_relative "parser"

class Evilution::AST::Pattern::Filter
  attr_reader :skipped_count

  def initialize(patterns)
    @matchers = patterns.map { |p| Evilution::AST::Pattern::Parser.new(p).parse }
    @skipped_count = 0
  end

  def skip?(node)
    if @matchers.any? { |m| m.match?(node) }
      @skipped_count += 1
      true
    else
      false
    end
  end

  def reset_count!
    @skipped_count = 0
  end
end
