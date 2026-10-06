# frozen_string_literal: true

require "prism"
require_relative "../heuristic"

# `index_to_fetch` turns `recv[key]` into `recv.fetch(key)`, which differs only
# when the key is absent. Under a guard that is truthy only when the key is
# there -- `if config[:k]`, `config.key?(:k) && ...` -- it cannot be absent, so
# the mutant behaves like the original and no test can kill it.
#
# The read in the guard itself is a different matter: `if config.fetch(:k)`
# raises where `if config[:k]` took the other branch. Only reads inside the
# guarded part match -- the branch a guard opens, or the statements after a
# guard that leaves (`return unless config[:k]`).
#
# A heuristic, not a proof: a hash with a default value passes the guard with
# the key absent, and a method-call receiver may answer with another object
# the second time.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch
  OPERATOR = "index_to_fetch"

  def match?(mutation)
    return false unless mutation.operator_name == OPERATOR

    path = NodePath.new.call(mutation)
    return false unless path

    read = IndexRead.from(path.last)
    return false unless read

    guarded?(path, read)
  end

  private

  # Walks outwards from the read. Each step asks whether the node just left
  # was the guarded part of its parent, or a statement that follows an early
  # exit in its parent's list; a scope the guard does not reach into ends the
  # walk.
  def guarded?(path, read)
    path.each_cons(2).reverse_each do |parent, child|
      return false if scope_boundary?(parent, read)
      return true if Guard.new(parent, read).protects?(child) || EarlyExit.new(parent, read).protects?(child)
    end
    false
  end

  # A nested method or lambda runs later, when the guard no longer speaks for
  # the receiver. A block runs in place, unless it declares the receiver's
  # name as its own variable.
  def scope_boundary?(node, read)
    case node
    when Prism::DefNode, Prism::LambdaNode then true
    when Prism::BlockNode then read.local_root? && node.locals.include?(read.root_name)
    else false
    end
  end
end

require_relative "guarded_index_fetch/node_path"
require_relative "guarded_index_fetch/index_read"
require_relative "guarded_index_fetch/condition"
require_relative "guarded_index_fetch/disturbance"
require_relative "guarded_index_fetch/guard"
require_relative "guarded_index_fetch/early_exit"
