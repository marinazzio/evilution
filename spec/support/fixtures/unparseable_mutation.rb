# frozen_string_literal: true

# Reliable source of an unparseable mutation: the `explicit_super_mutation`
# operator strips a positional splat from `super(*x, &block)` but leaves the
# trailing comma in place, producing `super(, &block)`. Used by the short-
# circuit guard to confirm the executor classifies unparseable mutations
# without invoking the isolator.
class UnparseableMutation
  def forward(*x, &block)
    super(*x, &block)
  end
end
