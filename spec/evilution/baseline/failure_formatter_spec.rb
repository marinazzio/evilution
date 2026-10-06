# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Baseline::FailureFormatter do
  subject(:formatter) { described_class.new }

  def example(id)
    Evilution::Baseline::ExampleFailure.new(id: id, description: "A works", message: "NameError: nope")
  end

  def failure(**)
    Evilution::Baseline::SpecFailure.new(spec_file: "spec/a_spec.rb", **)
  end

  it "lists each failing example with its first error line" do
    lines = formatter.call(failure(examples: [example("./spec/a_spec.rb[1:1]")], example_count: 1))

    expect(lines).to eq(["./spec/a_spec.rb[1:1] A works -- NameError: nope"])
  end

  it "says how many failing examples are not listed" do
    lines = formatter.call(failure(examples: [example("a"), example("b")], example_count: 5))

    expect(lines.last).to eq("... and 3 more failing")
  end

  it "does not mention a remainder when every failure is listed" do
    lines = formatter.call(failure(examples: [example("a"), example("b")], example_count: 2))

    expect(lines.length).to eq(2)
  end

  it "puts the error lines first" do
    lines = formatter.call(failure(error: "RuntimeError: boom\nline two", examples: [example("a")], example_count: 1))

    expect(lines).to eq(["RuntimeError: boom", "line two", "a A works -- NameError: nope"])
  end

  it "says so when nothing was captured" do
    expect(formatter.call(failure)).to eq(["no failure detail was captured"])
  end

  it "omits the separator for an example without a message" do
    bare = Evilution::Baseline::ExampleFailure.new(id: "a", description: "A works", message: "")

    expect(formatter.call(failure(examples: [bare], example_count: 1))).to eq(["a A works"])
  end

  it "names an example that has no description by its id alone" do
    bare = Evilution::Baseline::ExampleFailure.new(id: "FooTest#test_x", description: "", message: "nope")

    expect(formatter.call(failure(examples: [bare], example_count: 1))).to eq(["FooTest#test_x -- nope"])
  end
end
