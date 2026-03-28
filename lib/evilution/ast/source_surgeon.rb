# frozen_string_literal: true

require_relative "../ast"

module Evilution::AST::SourceSurgeon
  def self.apply(source, offset:, length:, replacement:)
    result = source.dup
    result[offset, length] = replacement
    result
  end
end
