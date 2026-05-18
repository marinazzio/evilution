# frozen_string_literal: true

require "prism"
require "evilution/ast/pattern/parser"

RSpec.describe Evilution::AST::Pattern::Parser do
  def parse(input)
    described_class.new(input).parse
  end

  def parse_node(code)
    Prism.parse(code).value.statements.body[0]
  end

  describe "#parse" do
    it "parses a bare node type" do
      matcher = parse("call")

      expect(matcher).to be_a(Evilution::AST::Pattern::NodeMatcher)
      expect(matcher.match?(parse_node("foo()"))).to be true
      expect(matcher.match?(parse_node('"hello"'))).to be false
    end

    it "parses node type with single attribute" do
      matcher = parse("call{name=log}")

      expect(matcher.match?(parse_node("log()"))).to be true
      expect(matcher.match?(parse_node("foo()"))).to be false
    end

    it "parses node type with multiple attributes" do
      matcher = parse("call{name=info, receiver=call{name=logger}}")

      expect(matcher.match?(parse_node("logger.info"))).to be true
      expect(matcher.match?(parse_node("foo.info"))).to be false
      expect(matcher.match?(parse_node("logger.debug"))).to be false
    end

    it "parses alternatives in attribute value" do
      matcher = parse("call{name=debug|info|warn}")

      expect(matcher.match?(parse_node("debug()"))).to be true
      expect(matcher.match?(parse_node("info()"))).to be true
      expect(matcher.match?(parse_node("warn()"))).to be true
      expect(matcher.match?(parse_node("error()"))).to be false
    end

    it "parses nested patterns" do
      matcher = parse("call{receiver=call{name=logger}}")

      expect(matcher.match?(parse_node("logger.info"))).to be true
      expect(matcher.match?(parse_node("foo.info"))).to be false
    end

    it "parses deeply nested patterns" do
      matcher = parse("call{receiver=call{receiver=constant_read{name=Rails}, name=logger}}")

      expect(matcher.match?(parse_node("Rails.logger.info"))).to be true
      expect(matcher.match?(parse_node("logger.info"))).to be false
    end

    it "parses _ wildcard" do
      matcher = parse("_")

      expect(matcher).to be_a(Evilution::AST::Pattern::AnyNodeMatcher)
      expect(matcher.match?(parse_node("foo()"))).to be true
    end

    it "parses ** deep wildcard" do
      matcher = parse("**")

      expect(matcher).to be_a(Evilution::AST::Pattern::DeepWildcardMatcher)
    end

    it "parses * wildcard value in attribute" do
      matcher = parse("call{receiver=*}")

      expect(matcher.match?(parse_node("obj.foo()"))).to be true
      expect(matcher.match?(parse_node("foo()"))).to be false
    end

    it "parses _ wildcard value in attribute" do
      matcher = parse("call{receiver=_}")

      expect(matcher.match?(parse_node("obj.foo()"))).to be true
      expect(matcher.match?(parse_node("foo()"))).to be false
    end

    it "parses ** deep wildcard value in attribute" do
      matcher = parse("call{receiver=**}")

      expect(matcher.match?(parse_node("obj.foo()"))).to be true
      expect(matcher.match?(parse_node("foo()"))).to be true
    end

    it "parses negation of value" do
      matcher = parse("call{name=!log}")

      expect(matcher.match?(parse_node("log()"))).to be false
      expect(matcher.match?(parse_node("info()"))).to be true
    end

    it "parses negation of nested pattern" do
      matcher = parse("call{receiver=!call{name=logger}}")

      expect(matcher.match?(parse_node("logger.info"))).to be false
      expect(matcher.match?(parse_node("foo.info"))).to be true
    end

    it "parses def node type" do
      matcher = parse("def{name=to_s}")
      code = "def to_s; end"
      tree = Prism.parse(code).value
      node = tree.statements.body[0]

      expect(matcher.match?(node)).to be true
    end

    it "parses constant_read node type" do
      matcher = parse("constant_read{name=ENV}")

      expect(matcher.match?(parse_node("ENV"))).to be true
      expect(matcher.match?(parse_node("Rails"))).to be false
    end

    it "handles whitespace in attributes" do
      matcher = parse("call{ name = log , receiver = call{ name = logger } }")

      expect(matcher.match?(parse_node("logger.log"))).to be true
    end

    it "raises on invalid syntax" do
      expect { parse("") }.to raise_error(Evilution::ConfigError, /invalid pattern/i)
      expect { parse("call{") }.to raise_error(Evilution::ConfigError, /unexpected end/i)
      expect { parse("call{name}") }.to raise_error(Evilution::ConfigError, /expected '='/i)
    end

    it "raises on unknown trailing characters" do
      expect { parse("call extra") }.to raise_error(Evilution::ConfigError, /unexpected/i)
    end

    it "strips surrounding whitespace from the input" do
      matcher = parse("  call  ")

      expect(matcher).to be_a(Evilution::AST::Pattern::NodeMatcher)
      expect(matcher.match?(parse_node("foo()"))).to be true
    end

    it "treats a whitespace-only input as an empty pattern" do
      expect { parse("   ") }.to raise_error(Evilution::ConfigError, /invalid pattern/i)
    end

    it "tolerates whitespace around every pattern token" do
      matcher = parse("  call { name = log , receiver = call { name = logger } }  ")

      expect(matcher.match?(parse_node("logger.log"))).to be true
    end

    it "tolerates whitespace after the alternative separator" do
      matcher = parse("call{name=debug| info| warn}")

      expect(matcher.match?(parse_node("debug()"))).to be true
      expect(matcher.match?(parse_node("info()"))).to be true
      expect(matcher.match?(parse_node("warn()"))).to be true
      expect(matcher.match?(parse_node("error()"))).to be false
    end

    it "parses a node pattern with empty braces" do
      matcher = parse("call{}")

      expect(matcher).to be_a(Evilution::AST::Pattern::NodeMatcher)
      expect(matcher.match?(parse_node("foo()"))).to be true
    end

    it "parses a node pattern with whitespace-only braces" do
      matcher = parse("call{  }")

      expect(matcher).to be_a(Evilution::AST::Pattern::NodeMatcher)
      expect(matcher.match?(parse_node("foo()"))).to be true
    end

    it "reports the unexpected characters from the failing position" do
      expect { parse("call @@@") }.to raise_error(
        Evilution::ConfigError, /position 5: @@@\z/
      )
    end

    it "treats an unknown single-character token as a node type" do
      expect { parse("z") }.to raise_error(Evilution::ConfigError, /unknown AST node type/i)
    end

    it "raises with an invalid-identifier message for a numeric leading char" do
      expect { parse("9call") }.to raise_error(
        Evilution::ConfigError, /invalid identifier/i
      )
    end

    it "raises an end-of-pattern error when the closing brace is missing" do
      expect { parse("call{name=foo") }.to raise_error(
        Evilution::ConfigError, /unexpected end/i
      )
    end

    it "parses an underscore-prefixed identifier as an attribute value" do
      matcher = parse("call{name=_x}")

      expect(matcher.attributes["name"]).to be_a(Evilution::AST::Pattern::ValueMatcher)
      expect(matcher.match?(parse_node("_x()"))).to be true
      expect(matcher.match?(parse_node("foo()"))).to be false
    end

    it "parses a single attribute value as a ValueMatcher" do
      matcher = parse("call{name=foo}")

      expect(matcher.attributes["name"]).to be_a(Evilution::AST::Pattern::ValueMatcher)
    end

    it "parses a star alternative as a literal entry of an AlternativesMatcher" do
      matcher = parse("call{name=foo|*}")
      value_matcher = matcher.attributes["name"]

      expect(value_matcher).to be_a(Evilution::AST::Pattern::AlternativesMatcher)
      expect(value_matcher.match_value?(:foo)).to be true
      expect(value_matcher.match_value?("*")).to be true
      expect(value_matcher.match_value?(:bar)).to be false
    end
  end
end
