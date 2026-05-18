# frozen_string_literal: true

require "prism"
require "evilution/ast/pattern/matcher"

RSpec.describe Evilution::AST::Pattern do
  def parse_node(code)
    Prism.parse(code).value.statements.body[0]
  end

  describe Evilution::AST::Pattern::NodeMatcher do
    it "matches a node by type" do
      matcher = described_class.new("call", {})
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be true
    end

    it "exposes the node type it was built with" do
      matcher = described_class.new("call", {})

      expect(matcher.node_type).to eq("call")
    end

    it "rejects a node that does not respond to the attribute" do
      matcher = described_class.new("call", {
                                      "definitely_not_an_attr" => Evilution::AST::Pattern::ValueMatcher.new("x")
                                    })
      node = parse_node("foo()")

      expect { matcher.match?(node) }.not_to raise_error
      expect(matcher.match?(node)).to be false
    end

    it "uses match_value? for value matchers that do not respond to match?" do
      value_only_matcher = Object.new
      def value_only_matcher.match_value?(actual) = actual.to_s == "foo"

      matcher = described_class.new("call", { "name" => value_only_matcher })

      expect(matcher.match?(parse_node("foo()"))).to be true
      expect(matcher.match?(parse_node("bar()"))).to be false
    end

    it "uses match? for value matchers that respond to match?" do
      probe = Object.new
      def probe.match?(actual) = actual.to_s == "foo"
      def probe.match_value?(_actual) = raise("match_value? must not be used")

      matcher = described_class.new("call", { "name" => probe })

      expect(matcher.match?(parse_node("foo()"))).to be true
      expect(matcher.match?(parse_node("bar()"))).to be false
    end

    it "does not match a different node type" do
      matcher = described_class.new("string", {})
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be false
    end

    it "matches node type with attribute constraint" do
      matcher = described_class.new("call", { "name" => Evilution::AST::Pattern::ValueMatcher.new("foo") })
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be true
    end

    it "rejects when attribute does not match" do
      matcher = described_class.new("call", { "name" => Evilution::AST::Pattern::ValueMatcher.new("bar") })
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be false
    end

    it "matches with nested pattern on receiver" do
      receiver_matcher = Evilution::AST::Pattern::NodeMatcher.new("call", {
                                                                    "name" => Evilution::AST::Pattern::ValueMatcher.new("logger")
                                                                  })
      matcher = described_class.new("call", { "receiver" => receiver_matcher })
      node = parse_node("logger.info")

      expect(matcher.match?(node)).to be true
    end

    it "rejects when nested pattern does not match" do
      receiver_matcher = Evilution::AST::Pattern::NodeMatcher.new("call", {
                                                                    "name" => Evilution::AST::Pattern::ValueMatcher.new("other")
                                                                  })
      matcher = described_class.new("call", { "receiver" => receiver_matcher })
      node = parse_node("logger.info")

      expect(matcher.match?(node)).to be false
    end

    it "matches with multiple attributes (AND)" do
      matcher = described_class.new("call", {
                                      "name" => Evilution::AST::Pattern::ValueMatcher.new("info"),
                                      "receiver" => Evilution::AST::Pattern::NodeMatcher.new("call", {
                                                                                               "name" => Evilution::AST::Pattern::ValueMatcher.new("logger")
                                                                                             })
                                    })
      node = parse_node("logger.info")

      expect(matcher.match?(node)).to be true
    end

    it "handles constant_read node type" do
      matcher = described_class.new("constant_read", {
                                      "name" => Evilution::AST::Pattern::ValueMatcher.new("Rails")
                                    })
      node = parse_node("Rails")

      expect(matcher.match?(node)).to be true
    end

    it "matches nil attribute with wildcard value" do
      matcher = described_class.new("call", {
                                      "receiver" => Evilution::AST::Pattern::WildcardValueMatcher.new
                                    })
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be false
    end

    it "matches present attribute with wildcard value" do
      matcher = described_class.new("call", {
                                      "receiver" => Evilution::AST::Pattern::WildcardValueMatcher.new
                                    })
      node = parse_node("obj.foo()")

      expect(matcher.match?(node)).to be true
    end
  end

  describe Evilution::AST::Pattern::AnyNodeMatcher do
    it "matches any node" do
      matcher = described_class.new
      node = parse_node("foo()")

      expect(matcher.match?(node)).to be true
    end

    it "matches a string node" do
      matcher = described_class.new
      node = parse_node('"hello"')

      expect(matcher.match?(node)).to be true
    end

    it "does not match nil" do
      matcher = described_class.new

      expect(matcher.match?(nil)).to be false
    end
  end

  describe Evilution::AST::Pattern::ValueMatcher do
    it "matches exact string value" do
      matcher = described_class.new("log")

      expect(matcher.match_value?(:log)).to be true
    end

    it "rejects non-matching value" do
      matcher = described_class.new("log")

      expect(matcher.match_value?(:info)).to be false
    end

    it "coerces both sides to string" do
      matcher = described_class.new("123")

      expect(matcher.match_value?(123)).to be true
    end
  end

  describe Evilution::AST::Pattern::AlternativesMatcher do
    it "matches any of the alternatives" do
      matcher = described_class.new(%w[debug info warn])

      expect(matcher.match_value?(:debug)).to be true
      expect(matcher.match_value?(:info)).to be true
      expect(matcher.match_value?(:warn)).to be true
    end

    it "rejects non-matching value" do
      matcher = described_class.new(%w[debug info])

      expect(matcher.match_value?(:error)).to be false
    end

    it "match? returns a strict boolean" do
      matcher = described_class.new(%w[debug info])

      expect(matcher.match?(:debug)).to be true
      expect(matcher.match?(:error)).to be false
    end
  end

  describe Evilution::AST::Pattern::NegationMatcher do
    it "negates a value matcher" do
      inner = Evilution::AST::Pattern::ValueMatcher.new("log")
      matcher = described_class.new(inner)

      expect(matcher.match_value?(:log)).to be false
      expect(matcher.match_value?(:info)).to be true
    end

    it "negates a node matcher" do
      inner = Evilution::AST::Pattern::NodeMatcher.new("call", {
                                                         "name" => Evilution::AST::Pattern::ValueMatcher.new("logger")
                                                       })
      matcher = described_class.new(inner)

      logger_node = parse_node("logger")
      other_node = parse_node("foo")

      expect(matcher.match?(logger_node)).to be false
      expect(matcher.match?(other_node)).to be true
    end
  end

  describe Evilution::AST::Pattern::DeepWildcardMatcher do
    it "matches any node" do
      matcher = described_class.new

      expect(matcher.match?(parse_node("foo"))).to be true
      expect(matcher.match?(nil)).to be true
    end
  end

  describe Evilution::AST::Pattern::WildcardValueMatcher do
    it "match_value? returns a strict boolean for any value" do
      matcher = described_class.new

      expect(matcher.match_value?(:anything)).to be true
      expect(matcher.match_value?(nil)).to be true
    end
  end
end
