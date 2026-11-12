# frozen_string_literal: true

class Gate
  def state
    "open"
  end

  # No example checks this, so its mutants survive -- if the runs after a run
  # that stopped at its kill still run their examples.
  def label
    "gate"
  end
end
