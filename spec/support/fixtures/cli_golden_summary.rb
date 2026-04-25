# frozen_string_literal: true

# Deterministic synthetic Summary fixture used by the CLI golden-output spec.
#
# This fixture exercises every conditional branch of
# `Evilution::Reporter::CLI#call` so that the captured output (committed in
# spec/evilution/reporter/cli/fixtures/) acts as a byte-for-byte regression
# net during the SOLID refactor (GH issue #847).
#
# IMPORTANT: All values are hard-coded. No Time.now, no rand, no env reads —
# the fixture must produce identical output on every machine and run.
#
# rubocop:disable Metrics/ModuleLength
module CliGoldenSummary
  Mutation = Struct.new(:operator_name, :file_path, :line, :unified_diff)
  Result = Struct.new(:mutation, :error?, :error_message)
  # CoverageGap mirrors Evilution::Result::CoverageGap which exposes a `count`
  # method; the CLI calls it directly so we must shadow Struct#count here.
  # rubocop:disable Lint/StructNewOverride
  CoverageGap = Struct.new(
    :file_path, :line, :subject_name, :single?, :primary_operator,
    :operator_names, :count, :mutation_results, :primary_diff
  )
  # rubocop:enable Lint/StructNewOverride
  Summary = Struct.new(
    :total, :killed, :survived, :timed_out, :neutral, :equivalent,
    :unresolved, :unparseable, :skipped, :score, :score_denominator,
    :duration, :efficiency, :mutations_per_second, :peak_memory_mb,
    :coverage_gaps, :neutral_results, :equivalent_results, :unresolved_results,
    :unparseable_results, :results, :disabled_mutations, :truncated?
  ) do
    def success?(min_score:)
      score >= min_score
    end
  end

  module_function

  def call(truncated: false)
    Summary.new(
      10, # total
      8,  # killed
      1,  # survived
      0,  # timed_out
      1,  # neutral
      1,  # equivalent
      1,  # unresolved
      1,  # unparseable
      1,  # skipped
      0.85, # score
      10,   # score_denominator
      2.5,  # duration
      0.34, # efficiency
      4.0,  # mutations_per_second
      120.5, # peak_memory_mb
      coverage_gaps,
      neutral_results,
      equivalent_results,
      unresolved_results,
      unparseable_results,
      errored_results,
      disabled_mutations,
      truncated
    ).freeze
  end

  def coverage_gaps
    [single_gap, multi_gap].freeze
  end

  def single_gap
    diff = "@@ -1,1 +1,1 @@\n-true\n+false"
    survived_mutation = Mutation.new(
      "BooleanFlip", "lib/foo.rb", 12,
      "@@ -1,1 +1,1 @@\n-true\n+false"
    )
    survived_result = Result.new(survived_mutation, false, nil)
    CoverageGap.new(
      "lib/foo.rb", 12, "Foo#bar", true, "BooleanFlip",
      ["BooleanFlip"], 1, [survived_result], diff
    )
  end

  def multi_gap
    diff = "@@ -2,2 +2,2 @@\n-x + 1\n+x - 1"
    mutation_a = Mutation.new(
      "ArithmeticReplace", "lib/baz.rb", 7,
      "@@ -2,2 +2,2 @@\n-x + 1\n+x - 1"
    )
    mutation_b = Mutation.new(
      "ConstantReplace", "lib/baz.rb", 7,
      "@@ -2,2 +2,2 @@\n-x + 1\n+x * 2"
    )
    result_a = Result.new(mutation_a, false, nil)
    result_b = Result.new(mutation_b, false, nil)
    CoverageGap.new(
      "lib/baz.rb", 7, "Baz#qux", false, "ArithmeticReplace",
      %w[ArithmeticReplace ConstantReplace], 2, [result_a, result_b], diff
    )
  end

  def neutral_results
    [Result.new(Mutation.new("StatementDeletion", "lib/n.rb", 3, nil), false, nil)].freeze
  end

  def equivalent_results
    [Result.new(Mutation.new("ScalarReturn", "lib/e.rb", 5, nil), false, nil)].freeze
  end

  def unresolved_results
    [Result.new(Mutation.new("BooleanFlip", "lib/u.rb", 8, nil), false, nil)].freeze
  end

  def unparseable_results
    [Result.new(Mutation.new("MethodBody", "lib/p.rb", 11, nil), false, nil)].freeze
  end

  # `summary.results` is filtered through `.select(&:error?)` by the CLI;
  # we include a mix of errored and non-errored results so the filter has
  # something to do, plus one errored result without an error_message to
  # exercise the "return header unless result.error_message" branch.
  def errored_results
    [
      Result.new(Mutation.new("BooleanFlip", "lib/ok.rb", 1, nil), false, nil),
      Result.new(
        Mutation.new("ArithmeticReplace", "lib/err.rb", 22, nil),
        true,
        "RuntimeError: kaboom\n  at lib/err.rb:22\n  at lib/err.rb:30"
      ),
      Result.new(
        Mutation.new("ConstantReplace", "lib/err2.rb", 4, nil),
        true,
        nil
      )
    ].freeze
  end

  def disabled_mutations
    [Mutation.new("BooleanFlip", "lib/disabled.rb", 99, nil)].freeze
  end
end
# rubocop:enable Metrics/ModuleLength
