# frozen_string_literal: true

# Measurement-only hook for the operator yield study (docs/operator_yield_study.md).
# Not part of the gem: it is loaded into an evilution run from the command line,
#
#   bundle exec ruby -r<path>/killsets_hook.rb <evilution>/exe/evilution run ...
#
# and does nothing unless one of its environment variables is set:
#
#   KILLSETS_OUT=<file.jsonl>  one JSON line per mutation run: file, line,
#                              operator, subject, diff and the ids of ALL the
#                              examples/tests that failed (the JSON report names
#                              only the first killer). Run with
#                              --no-stop-on-kill so the failing set is complete.
#   GENERATED_OUT=<file.jsonl> one JSON line per generated mutation BEFORE the
#                              planner's de-duplication: file, line, operator,
#                              diff and a digest of the mutated file. Shows
#                              which operator reports a mutation once the
#                              operator listed first for it is dropped. With
#                              GENERATED_ONLY=1 the run stops after planning.
#   DROP_OPERATORS=a,b         removes those operators from the registry.
#   DROP_VARIANTS=op:variant,  removes the generated mutations of those operator
#                              variants (variant names as in variants.rb).
#
# It is given after `bundle exec` (`-r` on the command line), not in RUBYOPT:
# it requires evilution, which has to resolve through the bundle.
require "json"
require "digest"
require "evilution"
require_relative "variants"

module KillSets
  def self.env_list(name) = ENV.fetch(name, "").split(",").map(&:strip).reject(&:empty?)

  def self.current = (Thread.current[:killsets_failed] ||= [])

  def self.append(path, row)
    File.open(path, "a") do |f|
      f.flock(File::LOCK_EX)
      f.write("#{JSON.generate(row)}\n")
    end
  end

  def self.subject_name(mutation)
    mutation.subject.name
  rescue StandardError
    nil
  end

  def self.record(mutation, result)
    out = ENV.fetch("KILLSETS_OUT", nil)
    return unless out

    append(out, file: mutation.file_path, line: mutation.line, operator: mutation.operator_name,
                subject: subject_name(mutation), diff: mutation.diff,
                passed: result.is_a?(Hash) ? result[:passed] : nil, failed: current.uniq)
  end

  module RunTests
    def run_tests(mutation)
      Thread.current[:killsets_failed] = []
      result = super
      KillSets.record(mutation, result)
      result
    end
  end

  module RSpecCollect
    private

    def build_result(status, command, detector)
      KillSets.current.concat(Evilution::Integration::RSpec::ExampleIds.failed(::RSpec.world))
      super
    end
  end

  module MinitestCollect
    private

    def run_minitest(args, detector)
      run = super
      KillSets.current.concat(Array(run[:failed_ids]))
      run
    end
  end

  module DropOperators
    def default
      registry = super
      drop = KillSets.env_list("DROP_OPERATORS")
      return registry if drop.empty?

      registry.instance_variable_get(:@operators).reject! { |op| drop.include?(op.operator_name.to_s) }
      registry
    end
  end

  module DropVariants
    def mutations_for(subject, **)
      drop = KillSets.env_list("DROP_VARIANTS")
      list = super
      return list if drop.empty?

      list.reject { |m| drop.include?("#{m.operator_name}:#{Variants.of(m.operator_name.to_s, m.diff)}") }
    end
  end

  module DumpGenerated
    private

    def deduplicate(mutations)
      out = ENV.fetch("GENERATED_OUT", nil)
      return super unless out

      mutations.each { |m| KillSets.append(out, KillSets.generated_row(m)) }
      exit(0) if ENV["GENERATED_ONLY"] == "1"
      super
    end
  end

  def self.generated_row(mutation)
    { file: mutation.file_path, line: mutation.line, operator: mutation.operator_name, diff: mutation.diff,
      mutated: Digest::SHA256.hexdigest(mutation.mutated_source) }
  end
end

Evilution::Integration::RSpec.prepend(KillSets::RunTests, KillSets::RSpecCollect)
Evilution::Integration::Minitest.prepend(KillSets::RunTests, KillSets::MinitestCollect)
Evilution::Mutator::Registry.singleton_class.prepend(KillSets::DropOperators)
Evilution::Mutator::Registry.prepend(KillSets::DropVariants)
Evilution::Runner::MutationPlanner.prepend(KillSets::DumpGenerated)
