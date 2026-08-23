# frozen_string_literal: true

require_relative "../loading"

# Suppresses exactly the Ruby warnings that re-evaluating a file is guaranteed
# to produce, and nothing else.
#
# Applying a mutation re-evaluates the file, which redefines its methods and
# reassigns its constants. Ruby reports that in verbose mode, and a project
# that also promotes warnings to exceptions -- dry-schema's `.rspec` carries
# `--warnings` while its spec_helper installs `Warning.process { |w| raise w }`
# -- fails every mutation on a message describing evilution's mechanism rather
# than the code under test.
#
# The blunt fix, `$VERBOSE = nil` around the eval, costs too much: the
# evaluated file then sees a different $VERBOSE than a normal load would (code
# branching on it takes the other path), and genuine warnings introduced BY a
# mutation are swallowed along with ours -- losing a kill that a raising
# handler would otherwise hand us. So the filter matches the specific
# mechanism messages instead and delegates everything else to whatever handler
# the project installed.
#
# EV-df7u / GH #1588.
class Evilution::Integration::Loading::ReevalWarningFilter
  MECHANISM_WARNINGS = Regexp.union(
    /method redefined; discarding old /,
    /already initialized constant /,
    /previous definition of .+ was here/
  ).freeze

  ACTIVE_KEY = :__evilution_reeval_warning_filter_active

  # Prepended to Warning's singleton, so it sits AHEAD of any handler the
  # project extended in (the `warning` gem extends Warning::Processor), and
  # `super` still reaches that handler for everything it does not drop.
  module Filter
    def warn(message, *args, **kwargs)
      filter = Evilution::Integration::Loading::ReevalWarningFilter
      return if filter.active? && filter.mechanism_warning?(message)

      super
    end
  end

  class << self
    def suppress
      install
      previous = Thread.current[ACTIVE_KEY]
      Thread.current[ACTIVE_KEY] = true
      yield
    ensure
      Thread.current[ACTIVE_KEY] = previous
    end

    def active?
      Thread.current[ACTIVE_KEY] ? true : false
    end

    def mechanism_warning?(message)
      MECHANISM_WARNINGS.match?(message)
    end

    # Idempotent: prepending twice would run the filter twice per warning.
    # `target` exists so a test can install into a throwaway module -- once
    # Warning's singleton has the filter there is no way to take it back off.
    def install(target = Warning.singleton_class)
      return if target.ancestors.include?(Filter)

      target.prepend(Filter)
    end
  end
end
