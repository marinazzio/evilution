# frozen_string_literal: true

require_relative "../ast"

module Evilution::AST::SourceSurgeon
  def self.apply(source, offset:, length:, replacement:)
    binary = source.b
    binary[offset, length] = replacement.b
    binary.force_encoding(source.encoding)
  end
end
