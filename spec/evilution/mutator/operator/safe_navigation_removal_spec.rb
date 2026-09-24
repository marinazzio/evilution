# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SafeNavigationRemoval do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/safe_navigation_removal.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["safe_navigation_removal", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces &. with a plain call" do
      expect(mutated_lines(mutations_for("plain"))).to eq(["user.name"])
    end

    it "keeps the arguments" do
      expect(mutated_lines(mutations_for("with_arguments"))).to eq(['user.fetch(:name, "anon")'])
    end

    it "keeps the block" do
      expect(mutated_lines(mutations_for("with_block"))).to eq(["items.map { |item| item }"])
    end

    it "mutates each link of a safe-navigation chain separately" do
      expect(mutated_lines(mutations_for("chained")))
        .to contain_exactly("user&.profile.name", "user.profile&.name")
    end

    it "mutates a safe-navigation attribute write" do
      expect(mutated_lines(mutations_for("attribute_write"))).to eq(["user.name = value"])
    end

    it "mutates a safe-navigation ||= write" do
      expect(mutated_lines(mutations_for("or_write"))).to eq(['user.name ||= "anon"'])
    end

    it "mutates a safe-navigation &&= write" do
      expect(mutated_lines(mutations_for("and_write"))).to eq(['user.name &&= "anon"'])
    end

    it "mutates a safe-navigation operator write" do
      expect(mutated_lines(mutations_for("operator_write"))).to eq(["counter.value += 1"])
    end

    it "descends into the value of a safe-navigation ||= write" do
      muts = mutations_from_source("def fill(a, b)\n  a&.x ||= b&.y\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("a.x ||= b&.y", "a&.x ||= b.y")
    end

    it "descends into the value of a safe-navigation &&= write" do
      muts = mutations_from_source("def fill(a, b)\n  a&.x &&= b&.y\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("a.x &&= b&.y", "a&.x &&= b.y")
    end

    it "descends into the value of a safe-navigation operator write" do
      muts = mutations_from_source("def bump(a, b)\n  a&.x += b&.y\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("a.x += b&.y", "a&.x += b.y")
    end

    it "emits nothing for a plain call" do
      expect(mutations_for("plain_call")).to be_empty
    end

    it "skips a self receiver, which is never nil" do
      expect(mutations_for("self_receiver")).to be_empty
    end

    it "skips literal receivers, which are never nil" do
      expect(mutations_for("literal_receivers")).to be_empty
    end

    it "still mutates a variable receiver next to a literal one" do
      muts = mutations_from_source("def pick(a)\n  [\"x\"&.size, a&.size]\nend\n")

      expect(mutated_lines(muts)).to eq(['["x"&.size, a.size]'])
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("plain").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("plain").map(&:operator_name).uniq).to eq(["safe_navigation_removal"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=name}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#plain") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
