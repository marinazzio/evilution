# frozen_string_literal: true

require "stringio"
require "evilution/cli/printers/subjects"

RSpec.describe Evilution::CLI::Printers::Subjects do
  let(:io) { StringIO.new }

  let(:entries) do
    [
      { name: "Foo#bar", file_path: "lib/foo.rb", line_number: 10, mutation_count: 3 },
      { name: "Baz#qux", file_path: "lib/baz.rb", line_number: 20, mutation_count: 1 }
    ]
  end

  it "prints each entry with name, file:line, and mutation count" do
    described_class.new(entries, total_mutations: 4).render(io)
    expect(io.string).to include("Foo#bar")
    expect(io.string).to include("lib/foo.rb:10")
    expect(io.string).to include("(3 mutations)")
    expect(io.string).to include("Baz#qux")
    expect(io.string).to include("lib/baz.rb:20")
    expect(io.string).to include("(1 mutation)")
  end

  it "prints a trailing summary line" do
    described_class.new(entries, total_mutations: 4).render(io)
    expect(io.string).to include("2 subjects, 4 mutations")
  end

  it "pluralizes subject and mutation labels for singular counts" do
    described_class.new(
      [{ name: "Foo#bar", file_path: "lib/foo.rb", line_number: 10, mutation_count: 1 }],
      total_mutations: 1
    ).render(io)
    expect(io.string).to include("(1 mutation)")
    expect(io.string).to include("1 subject, 1 mutation")
  end

  it "prints a blank separator line between entries and the summary" do
    described_class.new(entries, total_mutations: 4).render(io)
    lines = io.string.split("\n")
    expect(lines[lines.index("2 subjects, 4 mutations") - 1]).to eq("")
  end

  it "uses only the entry name in a row, not the whole entry hash" do
    described_class.new(entries, total_mutations: 4).render(io)
    row = io.string.split("\n").find { |l| l.include?("Foo#bar") }
    expect(row).not_to include(":file_path")
    expect(row).not_to include("=>")
  end

  it "does not render the inspected entry hash keys in a row" do
    described_class.new(entries, total_mutations: 4).render(io)
    row = io.string.split("\n").find { |l| l.include?("Foo#bar") }
    expect(row).not_to include("mutation_count:")
    expect(row).not_to include("line_number:")
    expect(row).not_to match(/\Aname:/)
  end

  it "renders the row beginning with the bare entry name" do
    described_class.new(entries, total_mutations: 4).render(io)
    row = io.string.split("\n").find { |l| l.include?("Foo#bar") }
    expect(row).to eq("  Foo#bar  lib/foo.rb:10  (3 mutations)")
  end
end
