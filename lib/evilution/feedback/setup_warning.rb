# frozen_string_literal: true

require_relative "../feedback"

# Detects "setup misconfiguration" patterns where mutation testing returned a
# result that is technically valid (score 0.0 with all-errored mutations) but
# is almost certainly the wrong score because the worker process couldn't
# evaluate any mutated source.
#
# Most common cause: MCP runs default to `preload: false` to keep the long-lived
# MCP server clean. Rails / Zeitwerk projects that depend on autoload then fail
# in every worker with `NameError: uninitialized constant ...`. The user sees
# "0% PASS-but-FAIL" with no obvious hint that they need to pass an explicit
# `preload: spec/rails_helper.rb` option.
#
# When triggered, this returns a warning string the MCP response can surface
# alongside the trimmed report — turning a silent wrong score into a loud
# pointer at the likely fix.
module Evilution::Feedback::SetupWarning
  module_function

  ERROR_DOMINANCE_THRESHOLD = 0.8
  ERROR_CLASS_CLUSTER_THRESHOLD = 0.8

  def call(summary)
    return nil if summary.nil?
    return nil unless errors_dominate?(summary)

    errored = summary.results.select(&:error?)
    dominant_class = dominant_error_class(errored)
    return nil unless dominant_class

    message_for(dominant_class, errored.size, summary.total)
  end

  def errors_dominate?(summary)
    return false if summary.total.zero?

    summary.errors.to_f / summary.total >= ERROR_DOMINANCE_THRESHOLD
  end
  private_class_method :errors_dominate?

  def dominant_error_class(errored_results)
    return nil if errored_results.empty?

    counts = errored_results.each_with_object(Hash.new(0)) do |result, acc|
      acc[result.error_class] += 1 if result.error_class
    end
    return nil if counts.empty?

    klass, count = counts.max_by { |_, v| v }
    return nil if count.to_f / errored_results.size < ERROR_CLASS_CLUSTER_THRESHOLD

    klass
  end
  private_class_method :dominant_error_class

  NAME_ERROR_HINT = "Most workers errored with NameError. This usually means autoloaded constants " \
                    "(Rails / Zeitwerk) weren't available when the mutation re-evaluated the source. " \
                    "Pass `preload: 'spec/rails_helper.rb'` (or your project's preload entry) so the " \
                    "MCP server requires it before forking workers."

  LOAD_ERROR_HINT = "Most workers errored with LoadError. A `require` in the mutated source path failed " \
                    "before any test ran. Check that the file's dependencies are reachable from the MCP " \
                    "server's load path, or pass `preload: '<entrypoint>'` to set them up."

  GENERIC_HINT_TEMPLATE = "Most workers errored with %<klass>s (%<count>d / %<total>d). The mutation " \
                          "score reflects this setup failure, not the test suite. Try the CLI for an " \
                          "independent reading, or pass `preload: '<path>'` if the failure is autoload-related."

  def message_for(klass, count, total)
    case klass.to_s
    when "NameError" then NAME_ERROR_HINT
    when "LoadError" then LOAD_ERROR_HINT
    else format(GENERIC_HINT_TEMPLATE, klass: klass, count: count, total: total)
    end
  end
  private_class_method :message_for
end
