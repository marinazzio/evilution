# frozen_string_literal: true

require "stringio"
require "json"
require "evilution/cli/printers/util_mutation"

RSpec.describe Evilution::CLI::Printers::UtilMutation do
  let(:subject_double) { instance_double("Subject", name: "Foo#bar") }
  let(:mutation) do
    instance_double(
      "Mutation",
      operator_name: "LiteralInt",
      subject: subject_double,
      file_path: "lib/a.rb",
      line: 10,
      diff: "- 1\n+ 2\n"
    )
  end
  let(:io) { StringIO.new }

  describe "text format" do
    it "prints numbered mutation entries" do
      described_class.new([mutation], format: :text).render(io)
      expect(io.string).to include("1. LiteralInt")
      expect(io.string).to include("Foo#bar")
      expect(io.string).to include("line 10")
    end

    it "prints the diff content" do
      described_class.new([mutation], format: :text).render(io)
      expect(io.string).to include("- 1")
      expect(io.string).to include("+ 2")
    end

    it "prints singular label for one mutation" do
      described_class.new([mutation], format: :text).render(io)
      expect(io.string).to include("1 mutation")
    end

    it "prints plural label for multiple mutations" do
      described_class.new([mutation, mutation], format: :text).render(io)
      expect(io.string).to include("2 mutations")
    end
  end

  describe "json format" do
    it "emits an array of mutation hashes" do
      described_class.new([mutation], format: :json).render(io)
      parsed = JSON.parse(io.string)
      expect(parsed.length).to eq(1)
      expect(parsed.first).to include(
        "operator" => "LiteralInt",
        "subject" => "Foo#bar",
        "file" => "lib/a.rb",
        "line" => 10,
        "diff" => "- 1\n+ 2\n"
      )
    end
  end
end
