# frozen_string_literal: true

require_relative "../json"

# One mutation's entry in a JSON report, whichever bucket it is listed under.
class Evilution::Reporter::JSON::MutationDetail
  # The mutations that point at a missing test, and get a suggestion for one:
  # those that ran and survived, and those no test executes at all.
  UNTESTED_STATUSES = %i[survived uncovered].freeze
  private_constant :UNTESTED_STATUSES

  def initialize(suggestion:, timings:)
    @suggestion = suggestion
    @timings = timings
  end

  def call(result)
    mutation = result.mutation
    detail = base_mutation_fields(mutation, result)
    append_survived_fields(detail, mutation) if UNTESTED_STATUSES.include?(result.status)
    detail[:test_command] = result.test_command if result.test_command
    append_memory_fields(detail, result)
    append_error_fields(detail, result)
    append_neutral_reason(detail, result)
    detail.merge!(@timings.mutation_fields(result))
  end

  private

  # Why a neutral was recorded — a red baseline and an infrastructure crash want
  # opposite responses, and both land in the same bucket (EV-5pob / GH #1606).
  def append_neutral_reason(detail, result)
    reason = result.neutral_reason
    return unless reason

    detail[:neutral_reason] = { kind: reason.kind.to_s, detail: reason.detail }
  end

  def base_mutation_fields(mutation, result)
    {
      operator: mutation.operator_name,
      file: mutation.file_path,
      line: mutation.line,
      status: result.status.to_s,
      duration: result.duration.round(4),
      diff: mutation.diff
    }
  end

  def append_survived_fields(detail, mutation)
    detail[:suggestion] = @suggestion.suggestion_for(mutation)
    unified = mutation.unified_diff
    detail[:unified_diff] = unified if unified
  end

  def append_memory_fields(detail, result)
    detail[:parent_rss_kb] = result.parent_rss_kb if result.parent_rss_kb
    detail[:child_rss_kb] = result.child_rss_kb if result.child_rss_kb
    detail[:memory_delta_kb] = result.memory_delta_kb if result.memory_delta_kb
  end

  def append_error_fields(detail, result)
    detail[:error_message] = result.error_message if result.error_message
    detail[:error_class] = result.error_class if result.error_class
    detail[:error_backtrace] = result.error_backtrace if result.error_backtrace
  end
end
