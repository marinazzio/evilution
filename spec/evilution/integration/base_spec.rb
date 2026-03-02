# frozen_string_literal: true

require "evilution/integration/base"

RSpec.describe Evilution::Integration::Base do
  it "raises NotImplementedError" do
    base = described_class.new

    expect { base.call(double("Mutation")) }.to raise_error(
      NotImplementedError, /must be implemented/
    )
  end
end
