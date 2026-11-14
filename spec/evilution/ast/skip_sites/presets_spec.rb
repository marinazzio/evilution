# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/presets"

RSpec.describe Evilution::AST::SkipSites::Presets do
  it "names every preset in the order skips are attributed" do
    expect(described_class.names).to eq(%i[logging debug_output error_messages requires])
  end

  it "builds the named presets in attribution order, whatever order they are named in" do
    expect(described_class.build(%i[requires logging]).map(&:name)).to eq(%i[logging requires])
  end

  it "builds none for no names" do
    expect(described_class.build([])).to eq([])
  end
end
