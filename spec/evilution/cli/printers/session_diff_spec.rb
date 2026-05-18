# frozen_string_literal: true

require "stringio"
require "json"
require "evilution/cli/printers/session_diff"

RSpec.describe Evilution::CLI::Printers::SessionDiff do
  let(:summary) do
    instance_double(
      "Session::Diff::Summary",
      base_score: 0.70, head_score: 0.85,
      base_killed: 7, base_total: 10, head_killed: 17, head_total: 20,
      score_delta: 0.15
    )
  end
  let(:fixed) do
    [{ "operator" => "LiteralInt", "file" => "lib/a.rb", "line" => 10, "subject" => "Foo#bar" }]
  end
  let(:new_survivors) do
    [{ "operator" => "Negation", "file" => "lib/b.rb", "line" => 5, "subject" => "Baz#qux" }]
  end
  let(:persistent) { [] }
  let(:result) do
    instance_double(
      "Session::Diff::Result",
      summary: summary, fixed: fixed, new_survivors: new_survivors, persistent: persistent,
      to_h: { "summary" => "x", "fixed" => fixed, "new_survivors" => new_survivors, "persistent" => persistent }
    )
  end
  let(:io) { StringIO.new }

  describe "text format" do
    it "prints the Session Diff header" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("Session Diff")
    end

    it "prints base and head scores and delta" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("70.00%")
      expect(io.string).to include("85.00%")
      expect(io.string).to include("+15.00%")
    end

    it "prints fixed section when non-empty" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("Fixed")
      expect(io.string).to include("LiteralInt")
      expect(io.string).to include("lib/a.rb:10")
    end

    it "prints new survivors section when non-empty" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("New survivors")
      expect(io.string).to include("Negation")
    end

    it "omits empty sections" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).not_to include("Persistent survivors")
    end

    it "prints the persistent survivors section when non-empty" do
      persistent_result = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: [], new_survivors: [],
        persistent: [{ "operator" => "Negation", "file" => "lib/c.rb",
                       "line" => 7, "subject" => "Qux#run" }],
        to_h: {}
      )
      described_class.new(persistent_result, format: :text).render(io)
      expect(io.string).to include("Persistent survivors (1):")
      expect(io.string).to include("lib/c.rb:7")
    end

    it "does not print 'No mutation changes' when a section is non-empty" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).not_to include("No mutation changes between sessions")
    end

    it "does not print 'No mutation changes' when only fixed is non-empty" do
      one_section = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: fixed, new_survivors: [], persistent: [], to_h: {}
      )
      described_class.new(one_section, format: :text).render(io)
      expect(io.string).not_to include("No mutation changes between sessions")
    end

    it "does not print 'No mutation changes' when only new survivors is non-empty" do
      one_section = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: [], new_survivors: new_survivors, persistent: [], to_h: {}
      )
      described_class.new(one_section, format: :text).render(io)
      expect(io.string).not_to include("No mutation changes between sessions")
    end

    it "does not print 'No mutation changes' when only persistent is non-empty" do
      one_section = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: [], new_survivors: [],
        persistent: [{ "operator" => "Negation", "file" => "lib/c.rb",
                       "line" => 7, "subject" => "Qux#run" }],
        to_h: {}
      )
      described_class.new(one_section, format: :text).render(io)
      expect(io.string).not_to include("No mutation changes between sessions")
    end

    it "prints 'No mutation changes' when all three lists are empty" do
      empty_result = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: [], new_survivors: [], persistent: [], to_h: {}
      )
      described_class.new(empty_result, format: :text).render(io)
      expect(io.string).to include("No mutation changes between sessions")
    end

    it "prints a 40-character rule under the header" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("=" * 40)
    end

    it "renders the section count, not the raw mutations array" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("Fixed (survived → killed) (1):")
      expect(io.string).not_to match(/\(\[\{/)
    end

    it "renders mutation lines with operator and subject values, not raw hashes" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to include("  LiteralInt — lib/a.rb:10  Foo#bar")
      expect(io.string).not_to match(/^\s+\{/)
    end

    it "separates the summary and sections with blank lines" do
      described_class.new(result, format: :text).render(io)
      expect(io.string).to match(/Delta:.*\n\n\e\[32m/)
    end

    it "prints a blank line before 'No mutation changes'" do
      empty_result = instance_double(
        "Session::Diff::Result",
        summary: summary, fixed: [], new_survivors: [], persistent: [], to_h: {}
      )
      described_class.new(empty_result, format: :text).render(io)
      expect(io.string).to match(/Delta:.*\n\nNo mutation changes/)
    end
  end

  describe "json format" do
    it "pretty-generates result.to_h" do
      described_class.new(result, format: :json).render(io)
      expect(JSON.parse(io.string)).to include("fixed")
    end
  end
end
