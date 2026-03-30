# frozen_string_literal: true

require_relative "../pattern"

module Evilution::AST::Pattern
  class NodeMatcher
    attr_reader :node_type, :attributes

    def initialize(node_type, attributes)
      @node_type = node_type
      @prism_class = resolve_prism_class(node_type)
      @attributes = attributes
    end

    def match?(node)
      return false unless node.is_a?(@prism_class)

      @attributes.all? { |attr_name, value_matcher| match_attribute?(node, attr_name, value_matcher) }
    end

    private

    def resolve_prism_class(type_name)
      class_name = "#{type_name.split("_").map(&:capitalize).join}Node"
      Prism.const_get(class_name)
    rescue NameError
      raise Evilution::ConfigError, "unknown AST node type: #{type_name}"
    end

    def match_attribute?(node, attr_name, value_matcher)
      return false unless node.respond_to?(attr_name)

      attr_value = node.public_send(attr_name)

      if value_matcher.respond_to?(:match?)
        value_matcher.match?(attr_value)
      else
        value_matcher.match_value?(attr_value)
      end
    end
  end

  class AnyNodeMatcher
    def match?(_node)
      true
    end
  end

  class DeepWildcardMatcher
    def match?(_node)
      true
    end
  end

  class ValueMatcher
    def initialize(value)
      @value = value
    end

    def match_value?(actual)
      actual.to_s == @value
    end

    def match?(node)
      match_value?(node)
    end
  end

  class AlternativesMatcher
    def initialize(values)
      @values = values
    end

    def match_value?(actual)
      actual_str = actual.to_s
      @values.any? { |v| actual_str == v }
    end

    def match?(node)
      match_value?(node)
    end
  end

  class WildcardValueMatcher
    def match_value?(_actual)
      true
    end

    def match?(node)
      !node.nil?
    end
  end

  class NegationMatcher
    def initialize(inner)
      @inner = inner
    end

    def match_value?(actual)
      !@inner.match_value?(actual)
    end

    def match?(node)
      !@inner.match?(node)
    end
  end
end
