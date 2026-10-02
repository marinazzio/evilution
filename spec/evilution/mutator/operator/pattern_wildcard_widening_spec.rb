# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::PatternWildcardWidening do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["pattern_wildcard_widening", ".rb"])
    tmpfile.write("class Matcher\n  def call(value, expected)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def in_clause(pattern)
    "    case value\n    in #{pattern} then 1\n    end\n"
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    context "with an array pattern" do
      it "lets the pattern accept longer arrays" do
        muts = mutations_for(in_clause("[first, second]"))

        expect(mutated_lines(muts)).to eq(["in [first, second, *] then 1"])
      end

      it "widens a deconstruct pattern, keeping its constant and delimiters" do
        expect(mutated_lines(mutations_for(in_clause("Point(x, y)")))).to eq(["in Point(x, y, *) then 1"])
        expect(mutated_lines(mutations_for(in_clause("Point[x, y]")))).to eq(["in Point[x, y, *] then 1"])
      end

      it "widens a pattern written without brackets" do
        muts = mutations_for(in_clause("Integer, String"))

        expect(mutated_lines(muts)).to eq(["in Integer, String, * then 1"])
      end

      it "widens a rightward assignment" do
        muts = mutations_for("    value => [first, second]\n    first\n")

        expect(mutated_lines(muts)).to eq(["value => [first, second, *]"])
      end

      it "widens a nested array pattern as well as the outer one" do
        muts = mutations_for(in_clause("[[a, b], c]"))

        expect(mutated_lines(muts)).to eq(
          ["in [[a, b], c, *] then 1", "in [[a, b, *], c] then 1"]
        )
      end

      # The pattern is open already, at whichever end the rest sits.
      it "emits nothing for a pattern that has a rest" do
        expect(mutations_for(in_clause("[first, *]"))).to be_empty
        expect(mutations_for(in_clause("[*init, last]"))).to be_empty
        expect(mutations_for(in_clause("[first, *middle, last]"))).to be_empty
      end

      it "emits nothing for an empty array pattern" do
        expect(mutations_for(in_clause("[]"))).to be_empty
      end

      it "emits nothing for a find pattern" do
        expect(mutations_for(in_clause("[*, :marker, *]"))).to be_empty
      end
    end

    context "with a hash pattern" do
      it "widens each value and drops each key" do
        muts = mutations_for(in_clause("{ name: String, age: Integer }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { name: _, age: Integer } then 1",
            "in { age: Integer } then 1",
            "in { name: String, age: _ } then 1",
            "in { name: String } then 1"
          ]
        )
      end

      # `in {}` matches the empty hash only, so removing the last key would
      # narrow the pattern rather than widen it.
      it "widens the value of a lone key without dropping it" do
        muts = mutations_for(in_clause("{ name: String }"))

        expect(mutated_lines(muts)).to eq(["in { name: _ } then 1"])
      end

      it "mutates a pattern written without braces" do
        muts = mutations_for(in_clause("name: String, age: Integer"))

        expect(mutated_lines(muts)).to eq(
          [
            "in name: _, age: Integer then 1",
            "in age: Integer then 1",
            "in name: String, age: _ then 1",
            "in name: String then 1"
          ]
        )
      end

      it "mutates a deconstruct pattern, keeping its constant" do
        muts = mutations_for(in_clause("Point(x: Integer, y: 0)"))

        expect(mutated_lines(muts)).to eq(
          [
            "in Point(x: _, y: 0) then 1",
            "in Point(y: 0) then 1",
            "in Point(x: Integer, y: _) then 1",
            "in Point(x: Integer) then 1"
          ]
        )
      end

      # Widening or dropping a pair that binds a variable takes the variable
      # away from the branch body, which then fails on the missing name
      # whatever the tests assert.
      it "leaves pairs that bind a variable alone" do
        muts = mutations_for(in_clause("{ name:, title: String => title, tags: [first, *], age: Integer }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { name:, title: String => title, tags: [first, *], age: _ } then 1",
            "in { name:, title: String => title, tags: [first, *] } then 1"
          ]
        )
      end

      it "emits nothing when every pair binds a variable" do
        expect(mutations_for(in_clause("{ name:, age: }"))).to be_empty
      end

      # An underscore name is a wildcard by convention: nothing reads it, so
      # the pair can be dropped, but its value is as wide as it gets.
      it "drops a pair whose value is already a wildcard without widening it" do
        muts = mutations_for(in_clause("{ name: String, age: _ }"))

        expect(mutated_lines(muts)).to eq(
          ["in { name: _, age: _ } then 1", "in { age: _ } then 1", "in { name: String } then 1"]
        )
      end

      it "treats any underscore name as a wildcard" do
        muts = mutations_for(in_clause("{ name: String, age: _ignored }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { name: _, age: _ignored } then 1",
            "in { age: _ignored } then 1",
            "in { name: String } then 1"
          ]
        )
      end

      # A shorthand key has no value pattern of its own to widen; the name it
      # binds stands in for one.
      it "does not widen a shorthand key bound to an underscore name" do
        expect(mutations_for(in_clause("{ _ignored: }"))).to be_empty

        muts = mutations_for(in_clause("{ name: String, _ignored: }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { name: _, _ignored: } then 1",
            "in { _ignored: } then 1",
            "in { name: String } then 1"
          ]
        )
      end

      it "treats a pinned value as one that binds nothing" do
        muts = mutations_for(in_clause("{ id: ^expected }"))

        expect(mutated_lines(muts)).to eq(["in { id: _ } then 1"])
      end

      it "keeps a named rest in place" do
        muts = mutations_for(in_clause("{ name: String, age: Integer, **rest }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { name: _, age: Integer, **rest } then 1",
            "in { age: Integer, **rest } then 1",
            "in { name: String, age: _, **rest } then 1",
            "in { name: String, **rest } then 1"
          ]
        )
      end

      it "opens a pattern closed with **nil" do
        muts = mutations_for(in_clause("{ name:, **nil }"))

        expect(mutated_lines(muts)).to eq(["in { name: } then 1"])
      end

      it "keeps **nil when dropping a key and drops it on its own" do
        muts = mutations_for(in_clause("{ kind: :a, size: 1, **nil }"))

        expect(mutated_lines(muts)).to eq(
          [
            "in { kind: _, size: 1, **nil } then 1",
            "in { size: 1, **nil } then 1",
            "in { kind: :a, size: _, **nil } then 1",
            "in { kind: :a, **nil } then 1",
            "in { kind: :a, size: 1 } then 1"
          ]
        )
      end

      # Both `{}` and `{ **nil }` match the empty hash only.
      it "emits nothing for a pattern that only has **nil" do
        expect(mutations_for(in_clause("{ **nil }"))).to be_empty
      end

      it "emits nothing for an empty hash pattern" do
        expect(mutations_for(in_clause("{}"))).to be_empty
      end

      it "mutates a hash pattern nested in an array pattern" do
        muts = mutations_for(in_clause("[{ id: Integer }, *]"))

        expect(mutated_lines(muts)).to eq(["in [{ id: _ }, *] then 1"])
      end
    end

    it "emits nothing for a case without patterns to widen" do
      expect(mutations_for(in_clause("Integer | String"))).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for(in_clause("{ kind: :a, pair: [Integer, String], **nil }"))

      expect(muts.length).to eq(6)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for(in_clause("[first, second]"))

      expect(muts.map(&:operator_name)).to eq(["pattern_wildcard_widening"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["array_pattern"])

      muts = mutations_for(in_clause("[first, second]"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
