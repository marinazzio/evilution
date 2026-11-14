# frozen_string_literal: true

require_relative "../ast"
require_relative "syntax_check"

module Evilution::AST::SourceSurgeon
  # region: what proved the source parses without it being parsed whole (see
  # .check); nil when it was.
  Result = Struct.new(:source, :status, :region, keyword_init: true) do
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

  # The block, when given, can prove the source parses for less than
  # parsing it whole, as AST::DefRegion#parse does for a mutation inside a
  # method. What it returns stands for the parse; when it is nil, the whole
  # source is parsed.
  def self.check(mutated)
    region = yield if block_given?
    return Result.new(source: mutated, status: :ok, region: region).freeze if region

    status = Evilution::AST::SyntaxCheck.valid?(mutated) ? :ok : :unparseable
    Result.new(source: mutated, status: status).freeze
  end
end
