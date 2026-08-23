# frozen_string_literal: true

require "evilution/diagnostic"

RSpec.describe Evilution::Diagnostic do
  describe ".warn" do
    it "writes the message to stderr" do
      expect { described_class.warn("[evilution] something") }
        .to output("[evilution] something\n").to_stderr
    end

    # EV-df7u / GH #1588: Kernel#warn routes through Warning.warn, which the
    # `warning` gem can be configured to raise from. A project doing that (dry-schema
    # and dry-monads both do in their spec_helper) would otherwise see evilution's
    # own advisory message promoted into a fatal error, failing a mutation we
    # deliberately classify as :unresolved.
    it "does not route through Warning, which a project may configure to raise" do
      allow(Warning).to receive(:warn).and_raise("promoted to an exception")

      expect { described_class.warn("[evilution] advisory") }.not_to raise_error
    end

    it "keeps writing when a project has made Kernel#warn fatal" do
      allow(Warning).to receive(:warn).and_raise("promoted to an exception")

      expect { described_class.warn("[evilution] advisory") }
        .to output(/advisory/).to_stderr
    end
  end
end
