# frozen_string_literal: true

module Evilution
  module Equivalent
    module Heuristic
      class MethodBodyNil
        def match?(mutation)
          return false unless mutation.operator_name == "method_body_replacement"

          node = mutation.subject.node
          return false unless node

          body = node.body
          return true if body.nil? || body.is_a?(Prism::NilNode)

          return body.body.first.is_a?(Prism::NilNode) if body.is_a?(Prism::StatementsNode) && body.body.length == 1

          false
        end
      end
    end
  end
end
