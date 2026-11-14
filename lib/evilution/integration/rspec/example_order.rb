# frozen_string_literal: true

require_relative "../rspec"
require_relative "example_ids"

# The order a mutation's run tries its examples in, when it stops at the
# first kill: the cost of a kill is whatever runs before it.
#
# First the examples that killed this mutation's neighbours earlier in the
# run, in the order they were given; then the rest, cheapest first by the time
# each took in the baseline. Examples without a time come last, and examples
# that compare equal keep the order they were defined in.
#
# RSpec asks an ordering for the examples of one group and, separately, for
# its child groups, so examples never leave their group and a group's
# `before(:context)` hooks still run once, around all of its examples. A group
# goes first when any example under it is a killer, otherwise by the time its
# examples take in all.
#
# Registered with RSpec under NAME and chosen with `--order NAME`. Outside a
# run (between #start and #finish) it keeps the order it is given, so a
# process whose global ordering it is left as runs everything as defined.
class Evilution::Integration::RSpec::ExampleOrder
  NAME = :evilution_killer_first
  UNKNOWN = Float::INFINITY
  private_constant :UNKNOWN

  # Whether RSpec runs an ordering named on the command line. An older one
  # ignores a name it does not know and keeps whatever order it had.
  def self.supported?
    defined?(::RSpec::Core::Ordering::Delayed) ? true : false
  end

  # durations: seconds per example id (see ExampleIds) from the baseline.
  def initialize(durations:)
    @durations = durations
    finish
  end

  # Whether there is anything to order by: without killers or durations every
  # example compares equal and the defined order stands.
  def informed?(killers)
    !(@durations.empty? && killers.empty?)
  end

  # killers: the ids of the examples to run first, the most telling first.
  def start(killers)
    @ranks = {}
    killers.each_with_index { |id, rank| @ranks[id] ||= rank }
    @ids = {}.compare_by_identity
    @active = true
  end

  def finish
    @active = false
    @ranks = {}
    @ids = {}.compare_by_identity
  end

  def order(items)
    return items unless @active

    items.each_with_index.sort_by { |item, index| [*key(item), index] }.map(&:first)
  end

  private

  def key(item)
    item.respond_to?(:descendant_filtered_examples) ? group_key(item) : example_key(item)
  end

  def example_key(example)
    id = (@ids[example] ||= Evilution::Integration::RSpec::ExampleIds.of(example))
    [@ranks.fetch(id, UNKNOWN), @durations.fetch(id, UNKNOWN)]
  end

  def group_key(group)
    keys = group.descendant_filtered_examples.map { |example| example_key(example) }
    [keys.map(&:first).min || UNKNOWN, keys.sum(&:last)]
  end
end
