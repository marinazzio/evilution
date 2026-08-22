# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Primitives do
  # Each example drives an anonymous Mutator::Base subclass so the primitives
  # are exercised through the same path a real operator uses: visit the node,
  # call the helper, let Base build the record.
  def mutations_for(code, &operator_body)
    Tempfile.create(["primitives", ".rb"]) do |file|
      file.write(code)
      file.flush

      node = Prism.parse(code).value.statements.body.first
      subject = Evilution::Subject.new(
        name: "Test#m", file_path: file.path, line_number: 1, source: code, node: node
      )

      Class.new(Evilution::Mutator::Base, &operator_body).new.call(subject)
    end
  end

  describe "#mutate_to_nil" do
    it "replaces the node's own span with nil" do
      muts = mutations_for("a && b") do
        def visit_and_node(node)
          mutate_to_nil(node)
          super
        end
      end

      expect(muts.map(&:mutated_source)).to eq(["nil"])
    end

    it "overwrites the target's span when target is given" do
      muts = mutations_for("if x\n  y\nend") do
        def visit_if_node(node)
          mutate_to_nil(node, target: node.statements)
          super
        end
      end

      expect(muts.first.mutated_source).to eq("if x\n  nil\nend")
    end

    it "attributes the mutation to the node, not the target" do
      muts = mutations_for("if x\n  y\nend") do
        def visit_if_node(node)
          mutate_to_nil(node, target: node.statements)
          super
        end
      end

      expect(muts.first.line).to eq(1)
    end

    it "skips when the target span is already nil" do
      muts = mutations_for("nil") do
        def visit_nil_node(node)
          mutate_to_nil(node)
          super
        end
      end

      expect(muts).to be_empty
    end

    it "skips when the target is absent" do
      muts = mutations_for("if x\nend") do
        def visit_if_node(node)
          mutate_to_nil(node, target: node.statements)
          super
        end
      end

      expect(muts).to be_empty
    end

    it "skips when the result does not parse in its surrounding context" do
      muts = mutations_for("def foo(a)\n  a\nend") do
        def visit_required_parameter_node(node)
          mutate_to_nil(node)
          super
        end
      end

      expect(muts).to be_empty
    end

    it "still honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      code = "log()"

      muts = Tempfile.create(["primitives", ".rb"]) do |file|
        file.write(code)
        file.flush

        node = Prism.parse(code).value.statements.body.first
        subject = Evilution::Subject.new(
          name: "Test#m", file_path: file.path, line_number: 1, source: code, node: node
        )
        operator = Class.new(Evilution::Mutator::Base) do
          def visit_call_node(node)
            mutate_to_nil(node)
            super
          end
        end.new

        operator.call(subject, filter: filter)
      end

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end

  describe "#promote_child" do
    it "replaces the node's span with the child's source" do
      muts = mutations_for("a && b") do
        def visit_and_node(node)
          promote_child(node, node.left)
          super
        end
      end

      expect(muts.map(&:mutated_source)).to eq(["a"])
    end

    it "copies the child's source verbatim, including its own punctuation" do
      muts = mutations_for("a && (b + c)") do
        def visit_and_node(node)
          promote_child(node, node.right)
          super
        end
      end

      expect(muts.map(&:mutated_source)).to eq(["(b + c)"])
    end

    it "overwrites the target's span when target is given" do
      muts = mutations_for("if x\n  a && b\nend") do
        def visit_if_node(node)
          and_node = node.statements.body.first
          promote_child(node, and_node.right, target: node.statements)
          super
        end
      end

      expect(muts.first.mutated_source).to eq("if x\n  b\nend")
    end

    it "attributes the mutation to the node, not the target" do
      muts = mutations_for("if x\n  a && b\nend") do
        def visit_if_node(node)
          and_node = node.statements.body.first
          promote_child(node, and_node.right, target: node.statements)
          super
        end
      end

      expect(muts.first.line).to eq(1)
    end

    it "skips when the child is absent" do
      muts = mutations_for("foo") do
        def visit_call_node(node)
          promote_child(node, node.receiver)
          super
        end
      end

      expect(muts).to be_empty
    end

    it "skips when the child's source is byte-identical to the target span" do
      muts = mutations_for("if x\n  y\nend") do
        def visit_if_node(node)
          promote_child(node.statements, node.statements.body.first)
          super
        end
      end

      expect(muts).to be_empty
    end

    it "skips when the promoted child does not parse in its surrounding context" do
      muts = mutations_for("foo(*a)") do
        def visit_call_node(node)
          return super if node.arguments.nil?

          promote_child(node, node.arguments.arguments.first)
          super
        end
      end

      expect(muts).to be_empty
    end
  end
end
