# frozen_string_literal: true

require_relative "../minitest"
require_relative "../stop_policy"

# Ends a mutation's Minitest run at its first decisive failure.
#
# Minitest has no switch to stop a run, so the hook sits in front of the
# method that runs one test and lets no further test start once the run's
# policy has stopped: the skipped tests are neither run nor recorded.
#
# The hook is installed for the whole process and asks whatever policy is set
# when each test starts. Only a mutation's own run sets one; between runs, and
# for the baseline and the canary, the policy is DISABLED and every test runs.
module Evilution::Integration::Minitest::StopHook
  # Minitest 6 runs each test through Runnable.run(klass, method_name, reporter).
  module Run
    def run(klass, method_name, reporter)
      return if Evilution::Integration::Minitest::StopHook.policy.stopped?

      super
    end
  end

  # Minitest 5 runs each test through run_one_method; its Runnable.run is the
  # suite runner.
  module RunOneMethod
    def run_one_method(klass, method_name, reporter)
      return if Evilution::Integration::Minitest::StopHook.policy.stopped?

      super
    end
  end

  @policy = Evilution::Integration::StopPolicy::DISABLED

  class << self
    # The current run's policy; DISABLED when no mutation run is under way.
    attr_accessor :policy

    def install!
      runnable = ::Minitest::Runnable.singleton_class
      runnable.prepend(hook) unless runnable.include?(hook)
    end

    # Minitest 6 is told apart by Runnable.run_suite, the suite runner it
    # split off from Runnable.run.
    def hook
      ::Minitest::Runnable.respond_to?(:run_suite) ? Run : RunOneMethod
    end
  end
end
