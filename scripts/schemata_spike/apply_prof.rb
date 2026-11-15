# frozen_string_literal: true

# Loaded with RUBYOPT=-r<this file>: times each step of applying a mutation and
# appends "step<TAB>ms<TAB>GCs" per call to the file named by APPLY_PROF.
require "bundler/setup"
require "evilution"
require "evilution/integration/loading/mutation_applier"
module ApplyProf
  OUT = ENV.fetch("APPLY_PROF")
  def self.wrap(klass, label, meth = :call)
    mod = Module.new do
      define_method(meth) do |*a, **k, &b|
        s = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        st = GC.stat(:count)
        begin
          super(*a, **k, &b)
        ensure
          ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - s) * 1000).round(3)
          File.open(OUT, "a") { |f| f.puts "#{label}\t#{ms}\t#{GC.stat(:count) - st}" }
        end
      end
    end
    klass.prepend(mod)
  end
  L = Evilution::Integration::Loading
  wrap L::SyntaxValidator, "syntax"
  wrap L::ConstantPinner, "pin"
  wrap L::ConcernStateCleaner, "concern"
  wrap L::SourceEvaluator, "eval"
  wrap L::RedefinitionRecovery, "recovery"
  wrap L::MutationApplier, "applier"
  wrap L::MutationApplier, "mark_feature", :mark_feature_loaded
end
