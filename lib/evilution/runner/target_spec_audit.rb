# frozen_string_literal: true

require_relative "../runner"

# Answers, in the parent process and before any mutation runs, which of the
# files evilution was pointed at resolve to no test file at all.
#
# The integrations resolve specs per mutation inside the worker, which is what
# produces `:unresolved` results, but that is a per-mutation fact diluted by
# every other file in the run: a target with no spec at all contributes a
# handful of unresolved mutations and disappears behind a healthy score
# (EV-p4sm / GH #1603). Asking the same selector once per file, up front, keeps
# the stronger fact — "you named this file and it was never tested" — intact.
#
# Only files that produced a subject are audited: a file evilution found
# nothing to mutate in — a constants-only file, say — has no untested behaviour
# to report, and failing a run over one would be noise.
#
# With `fallback_to_full_suite` a file without its own spec is run against the
# whole suite rather than skipped, so nothing goes untested and there is
# nothing to report.
class Evilution::Runner::TargetSpecAudit
  def initialize(config)
    @config = config
  end

  def call(file_paths)
    return [] if @config.fallback_to_full_suite?

    file_paths.uniq.sort.reject { |path| resolved?(path) }
  end

  private

  # SpecSelector answers nil when nothing resolves; a custom resolver plugged
  # in through it may answer an empty list instead.
  def resolved?(path)
    specs = @config.spec_selector.call(path)
    return false if specs.nil?

    !specs.empty?
  end
end
