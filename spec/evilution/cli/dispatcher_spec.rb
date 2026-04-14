# frozen_string_literal: true

require "evilution/cli/dispatcher"

RSpec.describe Evilution::CLI::Dispatcher do
  after do
    described_class.send(:commands).delete(:fake)
  end

  it "raises KeyError for an unknown command symbol" do
    expect { described_class.lookup(:nope_never_registered) }.to raise_error(KeyError, /nope_never_registered/)
  end

  it "registers and looks up a command class" do
    fake = Class.new
    described_class.register(:fake, fake)
    expect(described_class.lookup(:fake)).to eq(fake)
  end

  it "reports registered?" do
    fake = Class.new
    expect(described_class.registered?(:fake)).to be(false)
    described_class.register(:fake, fake)
    expect(described_class.registered?(:fake)).to be(true)
  end
end
