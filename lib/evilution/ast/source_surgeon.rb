# frozen_string_literal: true

require_relative "../ast"
require_relative "syntax_check"

module Evilution::AST::SourceSurgeon
  Result = Struct.new(:source, :status, keyword_init: true) do
    def ok?
      status == :ok
    end

    def unparseable?
      status == :unparseable
    end
  end

  def self.apply(source, offset:, length:, replacement:)
    binary = source.b
    binary[offset, length] = replacement.b
    mutated = binary.force_encoding(source.encoding)
    status = Evilution::AST::SyntaxCheck.valid?(mutated) ? :ok : :unparseable
    Result.new(source: mutated, status: status).freeze
  end
end
