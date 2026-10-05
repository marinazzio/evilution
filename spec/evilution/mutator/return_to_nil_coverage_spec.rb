# frozen_string_literal: true

# Replacing a `return` with "no return" — the early exit gone and nil where
# the return stood — is not an operator of its own: for every shape of
# `return` some existing operator already emits it. This pins that coverage,
# so a change to one of those operators cannot quietly reopen the gap.
RSpec.describe "return statements replaced by nil across the default registry" do
  def mutations_for(body)
    tmpfile = Tempfile.new(["return_to_nil", ".rb"])
    tmpfile.write("def m(x, xs)\n#{body}end\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    Evilution::Mutator::Registry.default.mutations_for(subject)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_body(mutation)
    mutation.mutated_source[/\Adef m\(x, xs\)\n(.*)end\n\z/m, 1]
  end

  {
    "a modifier guard" => ["  return :a if x\n  :b\n", "  nil if x\n  :b\n", "conditional_branch"],
    "an unless guard" => ["  return :a unless x\n  :b\n", "  nil unless x\n  :b\n", "conditional_branch"],
    "a bare guard" => ["  return if x\n  :b\n", "  nil if x\n  :b\n", "conditional_branch"],
    "the only statement of an if" => ["  if x\n    return :a\n  end\n  :b\n", "  if x\n    nil\n  end\n  :b\n", "conditional_branch"],
    "the last statement of an if" => [
      "  if x\n    log(x)\n    return :a\n  end\n  :b\n", "  if x\n    log(x)\n    \n  end\n  :b\n", "statement_deletion"
    ],
    "a return in a block" => ["  xs.each { |y| return y }\n  nil\n", "  xs.each { |y| nil }\n  nil\n", "block_body_to_nil"],
    "a return after or" => ["  x.valid? or return false\n  :b\n", "  x.valid?\n  :b\n", "boolean_operand_promotion"],
    "a return in a ternary" => ["  x ? (return :a) : log(x)\n  :b\n", "  x ? nil : log(x)\n  :b\n", "conditional_branch"],
    "a return in a when branch" => [
      "  case x\n  when 1 then return :a\n  end\n  :b\n", "  case x\n  when 1 then nil\n  end\n  :b\n", "case_when"
    ]
  }.each do |shape, (body, expected, operator)|
    it "reaches #{shape} through #{operator}" do
      mutation = mutations_for(body).find { |m| m.operator_name == operator && mutated_body(m) == expected }

      expect(mutation).not_to be_nil, "expected #{operator} to turn\n#{body}into\n#{expected}"
    end
  end
end
