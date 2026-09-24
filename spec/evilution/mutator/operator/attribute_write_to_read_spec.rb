# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::AttributeWriteToRead do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/attribute_write_to_read.rb", __dir__)
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
    tmpfile = Tempfile.new(["attribute_write_to_read", ".rb"])
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
    it "replaces an attribute write with a read" do
      expect(mutated_lines(mutations_for("only_write"))).to eq(["user.name"])
    end

    it "replaces a self attribute write with a read" do
      expect(mutated_lines(mutations_for("self_write"))).to eq(["self.name"])
    end

    it "keeps safe navigation on the read" do
      expect(mutated_lines(mutations_for("safe_write"))).to eq(["user&.name"])
    end

    it "replaces an index write with an index read" do
      expect(mutated_lines(mutations_for("index_write"))).to eq(["hash[:key]"])
    end

    it "mutates a write guarded by a modifier" do
      expect(mutated_lines(mutations_for("guarded_write"))).to eq(["user.name if value"])
    end

    it "mutates a write in value position" do
      expect(mutated_lines(mutations_for("value_position"))).to eq(["@last = (user.name)"])
    end

    it "mutates a write passed as an argument" do
      expect(mutated_lines(mutations_for("as_argument"))).to eq(["log(user.name)"])
    end

    it "skips a write that is one of several statements, which statement_deletion covers" do
      expect(mutations_for("in_multi_statement_body")).to be_empty
    end

    it "still mutates a write nested inside a statement of a multi-statement body" do
      muts = mutations_from_source("def run(user, v)\n  user.name = v if v\n  user.save\nend\n")

      expect(mutated_lines(muts)).to eq(["user.name if v"])
    end

    it "handles the explicit-parentheses setter form" do
      muts = mutations_from_source("def set(user, v)\n  user.name=(v)\nend\n")

      expect(mutated_lines(muts)).to eq(["user.name"])
    end

    it "drops a heredoc value together with its body" do
      muts = mutations_from_source("def set(user)\n  user.bio = <<~TXT\n    hi\n  TXT\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def set(user)\n  user.bio\nend\n"])
    end

    it "emits nothing for a plain read" do
      expect(mutations_for("plain_read")).to be_empty
    end

    it "emits nothing for a comparison operator ending in =" do
      expect(mutations_for("comparison")).to be_empty
    end

    it "reports the mutation on the line of the write" do
      expect(mutations_for("only_write").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("only_write").map(&:operator_name).uniq).to eq(["attribute_write_to_read"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#only_write") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
