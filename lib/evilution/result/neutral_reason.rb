# frozen_string_literal: true

require_relative "../result"

# Why a mutation was recorded neutral.
#
# Neutral covers two unrelated situations, and they call for opposite responses:
# a spec file that was already red before any mutation ran, and a test process
# that died on infrastructure rather than on the mutation. Without the reason
# they are indistinguishable in a report, and a run can print full marks while
# the neutral bucket quietly holds what would otherwise be survivors
# (EV-5pob / GH #1606).
Evilution::Result::NeutralReason = Data.define(:kind, :detail) do
  def self.baseline_failure(spec_file)
    new(kind: :baseline_failure, detail: spec_file)
  end

  def self.infra_error(error_class)
    new(kind: :infra_error, detail: error_class)
  end

  def to_s
    detail ? "#{label} (#{detail})" : label
  end

  private

  def label
    case kind
    when :baseline_failure then "baseline already failing"
    when :infra_error then "infrastructure error"
    else kind.to_s
    end
  end
end
