# frozen_string_literal: true

RSpec.describe Evilution do
  it "has a version number" do
    expect(Evilution::VERSION).not_to be nil
  end

  it "defines the Error class" do
    expect(Evilution::Error).to be < StandardError
  end
end
