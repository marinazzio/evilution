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

    context "with method names that are not plain identifiers" do
      it "parses a bang method name" do
        matcher = parse("call{name=strip_sources!}")

        expect(matcher.match?(parse_node("strip_sources!"))).to be true
        expect(matcher.match?(parse_node("strip_sources"))).to be false
      end

      it "parses a predicate method name" do
        matcher = parse("call{name=valid?}")

        expect(matcher.match?(parse_node("record.valid?"))).to be true
        expect(matcher.match?(parse_node("record.valid"))).to be false
      end

      it "parses a setter method name" do
        matcher = parse("call{name=value=}")

        expect(matcher.match?(parse_node("record.value = 1"))).to be true
        expect(matcher.match?(parse_node("record.value"))).to be false
      end

      it "parses suffixed names as alternatives" do
        matcher = parse("call{name=save!|valid?|save}")

        expect(matcher.match?(parse_node("save!"))).to be true
        expect(matcher.match?(parse_node("valid?"))).to be true
        expect(matcher.match?(parse_node("save"))).to be true
        expect(matcher.match?(parse_node("valid"))).to be false
      end

      it "parses a suffixed name next to other attributes" do
        matcher = parse("call{name=empty? , receiver=call{name=items}}")

        expect(matcher.match?(parse_node("items.empty?"))).to be true
        expect(matcher.match?(parse_node("other.empty?"))).to be false
      end

      it "negates a suffixed name" do
        matcher = parse("call{name=!valid?}")

        expect(matcher.match?(parse_node("valid?"))).to be false
        expect(matcher.match?(parse_node("valid"))).to be true
      end

      it "parses bare operator method names" do
        {
          "<=>" => "a <=> b", "===" => "a === b", "==" => "a == b", "=~" => "a =~ b",
          "[]=" => "a[1] = b", "[]" => "a[1]", "<=" => "a <= b", "<<" => "a << b", "<" => "a < b",
          ">=" => "a >= b", ">>" => "a >> b", ">" => "a > b", "+@" => "+a", "-@" => "-a",
          "+" => "a + b", "-" => "a - b", "/" => "a / b", "%" => "a % b", "&" => "a & b",
          "^" => "a ^ b", "~" => "~a"
        }.each do |name, code|
          matcher = parse("call{name=#{name}}")

          expect(matcher.match?(parse_node(code))).to be(true), "expected #{name} to match #{code}"
          expect(matcher.match?(parse_node("a.foo"))).to be(false), "expected #{name} not to match a.foo"
        end
      end

      it "takes the longest operator" do
        matcher = parse("call{name=<=>}")

        expect(matcher.match?(parse_node("a <=> b"))).to be true
        expect(matcher.match?(parse_node("a <= b"))).to be false
        expect(matcher.match?(parse_node("a < b"))).to be false
      end

      it "parses operators as alternatives" do
        matcher = parse("call{name=<|<=|>|>=}")

        expect(matcher.match?(parse_node("a < b"))).to be true
        expect(matcher.match?(parse_node("a >= b"))).to be true
        expect(matcher.match?(parse_node("a == b"))).to be false
      end

      it "negates an operator" do
        matcher = parse("call{name=!==}")

        expect(matcher.match?(parse_node("a == b"))).to be false
        expect(matcher.match?(parse_node("a != b"))).to be true
      end

      it "parses single-quoted names" do
        matcher = parse("call{name='|'}")

        expect(matcher.match?(parse_node("a | b"))).to be true
        expect(matcher.match?(parse_node("a & b"))).to be false
      end

      it "parses double-quoted names" do
        matcher = parse('call{name="!="}')

        expect(matcher.match?(parse_node("a != b"))).to be true
        expect(matcher.match?(parse_node("a == b"))).to be false
      end

      it "matches quoted names literally, without wildcard or negation meaning" do
        expect(parse("call{name='*'}").match?(parse_node("a * b"))).to be true
        expect(parse("call{name='*'}").match?(parse_node("a + b"))).to be false
        expect(parse("call{name='**'}").match?(parse_node("a ** b"))).to be true
        expect(parse("call{name='!'}").match?(parse_node("!a"))).to be true
        expect(parse("call{name='!~'}").match?(parse_node("a !~ b"))).to be true
      end

      it "parses quoted names as alternatives" do
        matcher = parse("call{name='|'|'&'|^}")

        expect(matcher.match?(parse_node("a | b"))).to be true
        expect(matcher.match?(parse_node("a & b"))).to be true
        expect(matcher.match?(parse_node("a ^ b"))).to be true
        expect(matcher.match?(parse_node("a + b"))).to be false
      end

      it "raises on an unterminated quoted name" do
        expect { parse("call{name='<=>}") }.to raise_error(
          Evilution::ConfigError, /unterminated quoted name starting at position 10/
        )
      end

      it "raises on an empty quoted name" do
        expect { parse("call{name=''}") }.to raise_error(
          Evilution::ConfigError, /empty quoted name at position 10/
        )
      end

      it "suggests quoting a name it cannot read" do
        expect { parse("call{name=`}") }.to raise_error(
          Evilution::ConfigError, /invalid name starting with '`' at position 10.*quote/
        )
      end

      it "keeps node types and attribute names to plain identifiers" do
        expect { parse("call?") }.to raise_error(Evilution::ConfigError, /unexpected characters at position 4/)
        expect { parse("call{name?=foo}") }.to raise_error(Evilution::ConfigError, /expected '='/)
      end
    end
  end
end
