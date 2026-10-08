# frozen_string_literal: true

require "evilution/reporter/suggestion"
require "evilution/reporter/suggestion/templates/rspec"

RSpec.describe Evilution::Reporter::Suggestion::Templates::Rspec do
  describe ".format_header" do
    def header(action)
      described_class.format_header(action, "a >= b", "a > b", "Foo#bar")
    end

    it "names the original, the mutated code and the subject of a change" do
      expect(header(:changed)).to eq("changed `a >= b` to `a > b` in Foo#bar")
    end

    it "names the original and the subject of a removal" do
      expect(header(:deleted)).to eq("deleted `a >= b` in Foo#bar")
      expect(header(:removed)).to eq("removed `a >= b` in Foo#bar")
      expect(header(:removed_superclass)).to eq("removed superclass from `a >= b` in Foo#bar")
      expect(header(:removed_ensure)).to eq("removed ensure block `a >= b` in Foo#bar")
    end

    it "returns nil for an unknown action" do
      expect(header(:renamed)).to be_nil
    end
  end

  describe ".build" do
    let(:mutation) do
      double("Mutation", subject: double("Subject", name: "Foo#bar"), diff: "- a >= b\n+ a > b",
                         file_path: "lib/foo.rb", line: 7)
    end

    it "renders an example headed by what the mutation changed and where" do
      template = described_class.build(it_desc: "checks the boundary in") { |name| "expect(subject.#{name}).to eq(1)\n" }

      expect(template.call(mutation)).to eq(<<~RSPEC.strip)
        # Mutation: changed `a >= b` to `a > b` in Foo#bar
        # lib/foo.rb:7
        it 'checks the boundary in #bar' do
          expect(subject.bar).to eq(1)
        end
      RSPEC
    end

    it "renders the header of the given action" do
      template = described_class.build(it_desc: "needs", action: :deleted) { |_name| "x\n" }

      expect(template.call(mutation).lines.first).to eq("# Mutation: deleted `a >= b` in Foo#bar\n")
    end
  end
end
