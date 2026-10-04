# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpNamedGroupRename do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["regexp_named_group_rename", ".rb"])
    tmpfile.write("def probe(s)\n#{body}end\n")
    tmpfile.flush
    described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(body, filter: nil)
    mutations_for(body, filter: filter).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "renames a named group so outside references to it break" do
      expect(mutated_lines("  s.match(/(?<user>\\w+)@/)[:user]\n")).to eq(["s.match(/(?<_user>\\w+)@/)[:user]"])
    end

    it "renames a group written with quotes" do
      expect(mutated_lines("  s.match(/(?'user'\\w+)@/)\n")).to eq(["s.match(/(?'_user'\\w+)@/)"])
    end

    it "renames each named group separately" do
      expect(mutated_lines("  s.match(/(?<user>\\w+)@(?<host>\\w+)/)\n")).to eq(
        ["s.match(/(?<_user>\\w+)@(?<host>\\w+)/)", "s.match(/(?<user>\\w+)@(?<_host>\\w+)/)"]
      )
    end

    # Only references outside the pattern should break: references inside it
    # are renamed along with the group.
    it "renames references inside the pattern along with the group" do
      expect(mutated_lines("  s.match(/(?<q>['\"]).*?\\k<q>/)\n")).to eq(["s.match(/(?<_q>['\"]).*?\\k<_q>/)"])
      expect(mutated_lines("  s.match(/(?<p>a\\g<p>?b)/)\n")).to eq(["s.match(/(?<_p>a\\g<_p>?b)/)"])
      expect(mutated_lines("  s.match(/(?'q'a)\\k'q'\\k<q+0>/)\n")).to eq(["s.match(/(?'_q'a)\\k'_q'\\k<_q+0>/)"])
    end

    it "renames every group that shares a name in one mutant" do
      expect(mutated_lines("  s.match(/(?<n>a)|(?<n>b)/)\n")).to eq(["s.match(/(?<_n>a)|(?<_n>b)/)"])
    end

    it "does not rename a reference to a different name that starts the same" do
      expect(mutated_lines("  s.match(/(?<n>a)(?<nn>b)\\k<nn>/)\n")).to eq(
        ["s.match(/(?<_n>a)(?<nn>b)\\k<nn>/)", "s.match(/(?<n>a)(?<_nn>b)\\k<_nn>/)"]
      )
    end

    it "picks a name that is not taken yet" do
      expect(mutated_lines("  s.match(/(?<user>a)(?<_user>b)/)\n")).to eq(
        ["s.match(/(?<__user>a)(?<_user>b)/)", "s.match(/(?<user>a)(?<__user>b)/)"]
      )
    end

    # `/(?<user>...)/ =~ s` also binds a local variable named after the group.
    it "renames the group of a matching assignment" do
      expect(mutated_lines("  user = nil\n  /(?<user>\\w+)@/ =~ s\n  user\n")).to eq(["/(?<_user>\\w+)@/ =~ s"])
    end

    it "leaves a pattern passed to match? or !~ alone" do
      expect(mutated_lines("  s.match?(/(?<user>\\w+)@/)\n")).to be_empty
      expect(mutated_lines("  /(?<user>\\w+)@/.match?(s)\n")).to be_empty
      expect(mutated_lines("  s !~ /(?<user>\\w+)@/\n")).to be_empty
    end

    it "handles match? called without arguments" do
      expect(mutated_lines("  s.match?\n  s.match(/(?<n>a)/)\n")).to eq(["s.match(/(?<_n>a)/)"])
    end

    it "leaves unnamed groups alone" do
      expect(mutated_lines("  s.match(/(a)(?:b)(?=c)/)\n")).to be_empty
    end

    it "leaves names written in a comment alone" do
      expect(mutated_lines("  s.match(/a # (?<n>x)\n/x)\n")).to be_empty
    end

    it "keeps the literal's delimiters, flags and multibyte text" do
      expect(mutated_lines("  s.match(%r{é(?<n>…)/}i)\n")).to eq(["s.match(%r{é(?<_n>…)/}i)"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_lines("  s.match(/(?<n>a)/)\n")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_lines("  s.match(/(?<n>\#{s})/)\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("  s.match(/(?<a>x)(?'b'y)\\k<a>/)\n")

      expect(muts.length).to eq(2)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_named_group_rename"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_lines("  s.match(/(?<n>a)/)\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
