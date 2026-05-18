# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Base do
  describe ".operator_name" do
    it "converts class name to snake_case" do
      stub_const("Evilution::Mutator::Operator::ComparisonReplacement", Class.new(described_class))

      expect(Evilution::Mutator::Operator::ComparisonReplacement.operator_name).to eq("comparison_replacement")
    end
  end

  describe "#call" do
    it "returns an empty array when no mutations are generated" do
      subject_obj = double("Subject",
                           file_path: File.expand_path("../../support/fixtures/simple_class.rb", __dir__),
                           node: Prism.parse("def foo\n  42\nend").value.statements.body.first)

      base = described_class.new
      result = base.call(subject_obj)

      expect(result).to eq([])
    end

    it "skips mutations when filter matches the node" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      code = "log()"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: fixture_path, node: node)

      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      operator = operator_class.new
      result = operator.call(subject_obj, filter: filter)

      expect(result).to be_empty
      expect(filter.skipped_count).to eq(1)
    end

    it "populates original_slice and mutated_slice from affected line range" do
      operator_class = Class.new(described_class) do
        def visit_integer_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "0",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      file_source = File.read(fixture_path)
      tree = Prism.parse(file_source).value
      subject_obj = double("Subject", name: "User#adult?", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)
      age_check = result.find { |m| m.line == 10 }

      expect(age_check).not_to be_nil
      expect(age_check.original_slice).to eq("    @age >= 18\n")
      expect(age_check.mutated_slice).to eq("    @age >= 0\n")
    end

    it "marks mutation parse_status :unparseable when Prism cannot parse mutated source" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.end_offset - 1,
            length: 1,
            replacement: "",
            node: node
          )
        end
      end

      code = "config[:font_size]\n"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: "x.rb", node: node)

      operator = operator_class.new
      operator.instance_variable_set(:@file_source, code)
      operator.instance_variable_set(:@filter, nil)
      operator.instance_variable_set(:@subject, subject_obj)
      operator.send(:add_mutation, offset: 17, length: 1, replacement: "", node: node)

      mutation = operator.mutations.first
      expect(mutation.parse_status).to eq(:unparseable)
      expect(mutation).to be_unparseable
    end

    it "marks parseable mutations with parse_status :ok" do
      operator_class = Class.new(described_class) do
        def visit_integer_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "0",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      tree = Prism.parse(File.read(fixture_path)).value
      subject_obj = double("Subject", name: "User#adult?", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)

      expect(result).not_to be_empty
      expect(result.map(&:parse_status).uniq).to eq([:ok])
    end

    it "populates slices spanning multi-line mutations" do
      operator_class = Class.new(described_class) do
        def visit_def_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      file_source = File.read(fixture_path)
      tree = Prism.parse(file_source).value
      subject_obj = double("Subject", name: "User#initialize", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)
      init_def = result.find { |m| m.line == 4 }

      expect(init_def).not_to be_nil
      expected_original = "  def initialize(name, age)\n    @name = name\n    @age = age\n  end\n"
      expect(init_def.original_slice).to eq(expected_original)
      expect(init_def.mutated_slice).to eq("  nil\n")
    end

    it "allows mutations when filter does not match" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      code = "info()"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: fixture_path, node: node)

      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      operator = operator_class.new
      result = operator.call(subject_obj, filter: filter)

      expect(result.length).to eq(1)
      expect(filter.skipped_count).to eq(0)
    end

    it "resets the mutations list between successive calls on the same subject" do
      operator_class = Class.new(described_class) do
        def visit_integer_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "0",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      tree = Prism.parse(File.read(fixture_path)).value
      subject_obj = double("Subject", name: "User#adult?", file_path: fixture_path, node: tree)

      operator = operator_class.new
      first = operator.call(subject_obj).length
      second = operator.call(subject_obj).length

      expect(first).to be_positive
      expect(second).to eq(first)
    end
  end

  describe "#add_mutation heredoc handling" do
    let(:heredoc_source) { "<<~MSG\n  body line\nMSG\n" }
    let(:heredoc_node) { Prism.parse(heredoc_source).value.statements.body.first }

    def build_operator(file_source)
      operator = described_class.new
      operator.instance_variable_set(:@file_source, file_source)
      operator.instance_variable_set(:@filter, nil)
      operator.instance_variable_set(:@subject, double("Subject", file_path: "x.rb"))
      operator
    end

    it "skips a mutation whose extended range and replacement both reference a heredoc anchor" do
      operator = build_operator(heredoc_source)

      operator.send(:add_mutation, offset: 0, length: 6, replacement: "<<~MSG\n  x\nMSG", node: heredoc_node)

      expect(operator.mutations).to be_empty
    end

    it "emits a mutation when the replacement references an anchor but the range needs no extension" do
      plain_source = "a = 1\n"
      node = Prism.parse(plain_source).value.statements.body.first.value
      operator = build_operator(plain_source)

      operator.send(:add_mutation, offset: 4, length: 1, replacement: "<<~MSG", node: node)

      expect(operator.mutations.length).to eq(1)
    end

    it "emits a mutation when the range needs extension but the replacement has no anchor" do
      operator = build_operator(heredoc_source)

      operator.send(:add_mutation, offset: 0, length: 6, replacement: "nil", node: heredoc_node)

      expect(operator.mutations.length).to eq(1)
    end

    it "extends the mutated range to sweep the orphaned heredoc body and terminator" do
      operator = build_operator(heredoc_source)

      operator.send(:add_mutation, offset: 0, length: 6, replacement: "nil", node: heredoc_node)

      expect(operator.mutations.first.mutated_source).to eq("nil\n")
    end
  end

  describe "#build_eval_source" do
    let(:operator) do
      op = described_class.new
      op.instance_variable_set(:@subject, double("Subject", file_path: "x.rb"))
      op
    end

    it "returns the raw mutated source for unparseable surgery" do
      surgery = Evilution::AST::SourceSurgeon.apply("a = 1\n", offset: 0, length: 1, replacement: "@")

      expect(surgery).not_to be_ok
      expect(operator.send(:build_eval_source, surgery)).to eq(surgery.source)
    end

    it "returns a neutralized String for parseable surgery" do
      surgery = Evilution::AST::SourceSurgeon.apply("a = 1\n", offset: 4, length: 1, replacement: "2")

      result = operator.send(:build_eval_source, surgery)

      expect(result).to be_a(String)
      expect(result).to eq("a = 2\n")
    end
  end

  describe "#byteslice_source" do
    it "returns the requested byte range of the file source" do
      operator = described_class.new
      operator.instance_variable_set(:@file_source, "abcdefgh")

      expect(operator.send(:byteslice_source, 2, 3)).to eq("cde")
    end
  end

  describe "#slice_affected_lines" do
    def slice_for(file_source, mutated_source:, offset:, length:, replacement_bytesize:)
      operator = described_class.new
      operator.instance_variable_set(:@file_source, file_source)
      operator.send(
        :slice_affected_lines,
        mutated_source: mutated_source,
        offset: offset,
        length: length,
        replacement_bytesize: replacement_bytesize
      )
    end

    it "extends the mutated slice across a multi-line replacement" do
      slices = slice_for(
        "p 1\n",
        mutated_source: "p (\nA\n)\n",
        offset: 2,
        length: 1,
        replacement_bytesize: 5
      )

      expect(slices.original).to eq("p 1\n")
      expect(slices.mutated).to eq("p (\nA\n)\n")
    end

    it "slices a single line that has no trailing newline" do
      slices = slice_for(
        "value = 42",
        mutated_source: "value = 0",
        offset: 8,
        length: 2,
        replacement_bytesize: 1
      )

      expect(slices.original).to eq("value = 42")
      expect(slices.mutated).to eq("value = 0")
    end
  end

  describe ".operator_name with consecutive capitals" do
    it "splits an acronym prefix from the following word" do
      stub_const("Evilution::Mutator::Operator::ASTReplacement", Class.new(described_class))

      expect(Evilution::Mutator::Operator::ASTReplacement.operator_name).to eq("ast_replacement")
    end
  end

  describe ".parsed_tree_for" do
    around do |example|
      saved = described_class.instance_variable_get(:@parse_cache)
      described_class.instance_variable_set(:@parse_cache, {})
      example.run
      described_class.instance_variable_set(:@parse_cache, saved)
    end

    it "returns a parsed Prism program node" do
      tree = described_class.parsed_tree_for("a.rb", "x = 1\n")

      expect(tree).to be_a(Prism::ProgramNode)
    end

    it "returns the same cached tree object for an unchanged source" do
      first = described_class.parsed_tree_for("a.rb", "x = 1\n")
      second = described_class.parsed_tree_for("a.rb", "x = 1\n")

      expect(second).to equal(first)
    end

    it "re-parses when the source for a path changes" do
      first = described_class.parsed_tree_for("a.rb", "x = 1\n")
      second = described_class.parsed_tree_for("a.rb", "y = 2\n")

      expect(second).not_to equal(first)
      expect(second).to be_a(Prism::ProgramNode)
    end
  end

  describe ".clear_parse_cache!" do
    around do |example|
      saved = described_class.instance_variable_get(:@parse_cache)
      described_class.instance_variable_set(:@parse_cache, {})
      example.run
      described_class.instance_variable_set(:@parse_cache, saved)
    end

    it "empties the cache so the next parse produces a fresh tree" do
      first = described_class.parsed_tree_for("a.rb", "x = 1\n")
      described_class.clear_parse_cache!
      second = described_class.parsed_tree_for("a.rb", "x = 1\n")

      expect(second).not_to equal(first)
    end
  end
end
