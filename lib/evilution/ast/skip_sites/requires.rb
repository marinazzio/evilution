# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"
require_relative "nodes"

# `require` and `require_relative` that run while the file loads: at the top
# of the file or in a class or module body, sent to no receiver or to
# Kernel. By the time a mutant is evaluated the file has been loaded once
# already, so dropping or changing such a require changes nothing the tests
# can see, and the mutant survives for no reason worth reporting. A require
# inside a method, block or lambda loads lazily and is left alone: it runs
# when the code under test runs. A condition guarding a require is not part
# of the site.
#
# Every mutation inside a site is skipped, the call itself included.
class Evilution::AST::SkipSites::Requires
  REQUIRES = %i[require require_relative].freeze
  DEFERRED = [Prism::DefNode, Prism::BlockNode, Prism::LambdaNode].freeze
  private_constant :REQUIRES, :DEFERRED

  def name
    :requires
  end

  # chain: the mutated node, then its ancestors, nearest first.
  def covers?(chain)
    chain.each_with_index.any? do |node, index|
      Evilution::AST::SkipSites::Nodes.kernel_call?(node, REQUIRES) && runs_on_load?(chain, index)
    end
  end

  private

  def runs_on_load?(chain, site_index)
    chain.drop(site_index + 1).none? { |ancestor| DEFERRED.any? { |type| ancestor.is_a?(type) } }
  end
end
