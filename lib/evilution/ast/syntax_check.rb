# frozen_string_literal: true

require "prism"

require_relative "../ast"

# Answers whether mutated source is Ruby the running interpreter will accept.
#
# Mutations are built and screened with Prism, but Prism and the older
# parse.y parser do not agree on everything: Prism takes a bare constant
# operator write inside a method (`def f; LIMIT ||= 1; end`) and a `nil[...]`
# pattern, both of which parse.y rejects. An interpreter that compiles with
# parse.y -- Ruby 3.3 by default, any later one started with
# `--parser=parse.y` -- would be handed a mutant marked parseable and raise
# SyntaxError evaluating it.
#
# So Prism decides first, and where the interpreter does not compile with
# Prism, parse.y is asked as well. That second parse costs about what the
# first does and is only paid on those interpreters.
module Evilution::AST::SyntaxCheck
  # How the interpreter says it compiles: `ruby 3.4.1 (...) +PRISM [...]`.
  PRISM_INTERPRETER = RUBY_DESCRIPTION.include?("+PRISM")

  def self.valid?(source, prism_interpreter: PRISM_INTERPRETER)
    return false unless Prism.parse(source).success?

    prism_interpreter || parse_y_accepts?(source)
  end

  # RubyVM::AbstractSyntaxTree is built on parse.y whatever the interpreter
  # compiles with. It is CRuby's own: another implementation has no parse.y
  # to ask, and there Prism's answer stands, as it does after a failure that
  # is not about syntax.
  def self.parse_y_accepts?(source)
    return true unless defined?(RubyVM::AbstractSyntaxTree)

    without_warnings { RubyVM::AbstractSyntaxTree.parse(source) }
    true
  rescue SyntaxError
    false
  rescue StandardError
    true
  end

  # parse.y warns as it parses ("possibly useless use of == in void
  # context"), which a mutant earns far more often than written code does.
  def self.without_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  private_class_method :parse_y_accepts?, :without_warnings
end
