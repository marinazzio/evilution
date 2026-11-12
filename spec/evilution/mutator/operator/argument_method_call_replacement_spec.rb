# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/argument_method_call_replacement"

RSpec.describe Evilution::Mutator::Operator::ArgumentMethodCallReplacement do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/argument_method_call_replacement.rb", __dir__)
  end
  let(:subjects) { parser.call(fixture_path) }

  def subject_named(name)
    subjects.find { |s| s.name.include?(name) }
  end

  def diffs_for(method_name)
    described_class.new.call(subject_named(method_name)).map(&:diff)
  end

  describe "#call" do
    it "drops a method call from a positional argument (fn(x.attr) -> fn(x))" do
      expect(diffs_for("call_arg")).to include(match(/-\s*log\(parsed\.from_id\).*\+\s*log\(parsed\)/m))
    end

    it "drops a method call inside a hash value" do
      expect(diffs_for("hash_value"))
        .to include(match(/-\s*log\(\{ from_id: parsed\.from_id \}\.to_json\).*\+\s*log\(\{ from_id: parsed \}\.to_json\)/m))
    end

    it "drops a method call inside an array element" do
      expect(diffs_for("array_element")).to include(match(/parsed\.from_id, other\.name/))
      expect(diffs_for("array_element")).to include(match(/parsed, other\.name/))
    end

    it "drops the trailing method on a chained call (a.b.c -> a.b)" do
      expect(diffs_for("chained_call")).to include(match(/-\s*log\(a\.b\.c\).*\+\s*log\(a\.b\)/m))
    end

    it "drops a method call with a block argument" do
      expect(diffs_for("call_with_block")).to include(match(/-\s*log\(parsed\.attrs \{ \|x\| x \}\).*\+\s*log\(parsed\)/m))
    end

    it "drops a method call from a keyword argument value" do
      expect(diffs_for("nested_in_kwarg")).to include(match(/-\s*log\(payload: parsed\.from_id\).*\+\s*log\(payload: parsed\)/m))
    end

    it "does not fire on arguments that are not method calls" do
      expect(diffs_for("no_receiver_arg")).to be_empty
    end

    it "does not fire on calls with no arguments" do
      expect(diffs_for("no_args_call")).to be_empty
    end

    it "does not descend into a double-splat hash entry (only AssocNode values mutate)" do
      tmpfile = Tempfile.new(["amcr_splat", ".rb"])
      tmpfile.write("def m\n  log(**build.opts, a: parsed.from_id)\nend\n")
      tmpfile.close
      splat_subjects = parser.call(tmpfile.path)
      mutations = splat_subjects.flat_map { |s| described_class.new.call(s) }

      expect(mutations.length).to eq(1)
      expect(mutations.first.mutated_source).to include("**build.opts")
      expect(mutations.first.mutated_source).to include("a: parsed)")
    ensure
      tmpfile.unlink if tmpfile
    end

    def mutations_from_source(src)
      tmpfile = Tempfile.new(["amcr_nested", ".rb"])
      tmpfile.write(src)
      tmpfile.close
      nested_subjects = parser.call(tmpfile.path)
      nested_subjects.flat_map { |s| described_class.new.call(s) }
    ensure
      tmpfile.unlink if tmpfile
    end

    it "descends into a call argument nested inside an array literal" do
      mutations = mutations_from_source("def m\n  x = [wrap(inner.x)]\n  x\nend\n")

      expect(mutations.map(&:mutated_source)).to include(a_string_matching(/wrap\(inner\)/))
    end

    it "descends into a call argument nested inside a hash literal value" do
      mutations = mutations_from_source("def m\n  x = { k: wrap(inner.x) }\n  x\nend\n")

      expect(mutations.map(&:mutated_source)).to include(a_string_matching(/wrap\(inner\)/))
    end

    it "descends into a call argument nested inside a keyword-hash argument" do
      mutations = mutations_from_source("def m\n  log(k: wrap(inner.x))\nend\n")

      expect(mutations.map(&:mutated_source)).to include(a_string_matching(/wrap\(inner\)/))
    end

    it "produces parseable Ruby for every mutation" do
      subjects.each do |s|
        described_class.new.call(s).each do |mutation|
          parse = Prism.parse(mutation.mutated_source)
          expect(parse.errors).to be_empty,
                                  "invalid Ruby: #{mutation.mutated_source.inspect}; errors: #{parse.errors.map(&:message).join(", ")}"
        end
      end
    end

    context "with a constant's value" do
      def constant_mutations(inline_source)
        Tempfile.create(["argument_method_call_replacement", ".rb"]) do |file|
          file.write(inline_source)
          file.flush
          parser.call(file.path).select { |s| s.kind == :constant_write }.flat_map { |s| described_class.new.call(s) }
        end
      end

      def constant_lines(inline_source)
        constant_mutations(inline_source).map { |m| m.mutated_source.lines[m.line - 1].strip }
      end

      it "runs on constant-write subjects as well as the default kinds" do
        expect(described_class.subject_kinds).to eq(%i[method scope aasm callback constant_write])
      end

      it "drops a method call inside a hash value" do
        expect(constant_lines("class C\n  MAP = { seat: \"1\".to_i }\nend\n")).to contain_exactly("MAP = { seat: \"1\" }")
      end

      it "leaves a frozen element to freeze_removal" do
        expect(constant_lines("class C\n  LIST = [a.freeze, b.to_s]\nend\n")).to contain_exactly("LIST = [a.freeze, b]")
      end

      it "leaves a method defined in the value to that method's own subject" do
        expect(constant_lines("class C\n  H = Class.new do\n    def go(a) = log(a.to_i)\n  end\nend\n")).to be_empty
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(subject_named("call_arg"))

      expect(mutations.first.operator_name).to eq("argument_method_call_replacement")
    end
  end
end
