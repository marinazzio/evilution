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
    check(splice(source, offset: offset, length: length, replacement: replacement))
  end

  # The source with the bytes replaced, not yet checked: cheap next to the
  # parse that checking takes.
  def self.splice(source, offset:, length:, replacement:)
    binary = source.b
    binary[offset, length] = replacement.b
    binary.force_encoding(source.encoding)
  end

  def self.check(mutated)
    status = Evilution::AST::SyntaxCheck.valid?(mutated) ? :ok : :unparseable
    Result.new(source: mutated, status: status).freeze
  end
end
