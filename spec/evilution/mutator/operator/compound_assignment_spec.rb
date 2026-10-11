# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CompoundAssignment do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/compound_assignment.rb", __dir__) }
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

  describe "#call" do
    it "replaces += with -=" do
      muts = mutations_for("add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x -= 1") }).to be true
    end

    it "replaces += with *=" do
      muts = mutations_for("add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 1") }).to be true
    end

    it "replaces -= with +=" do
      muts = mutations_for("sub_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x += 1") }).to be true
    end

    it "replaces *= with /=" do
      muts = mutations_for("mul_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x /= 2") }).to be true
    end

    it "replaces /= with *=" do
      muts = mutations_for("div_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 2") }).to be true
    end

    it "replaces %= with *=" do
      muts = mutations_for("mod_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 3") }).to be true
    end

    it "replaces **= with *=" do
      muts = mutations_for("pow_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 2") }).to be true
    end

    it "generates correct number of mutations for +=" do
      muts = mutations_for("add_assign")

      # 2 swaps (-, *) + 1 removal = 3
      expect(muts.length).to eq(3)
    end

    it "generates two mutations for single-swap operators" do
      muts = mutations_for("mod_assign")

      # 1 swap + 1 removal = 2
      expect(muts.length).to eq(2)
    end

    it "mutates instance variable compound assignments" do
      muts = mutations_for("ivar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("@count -= 1") }).to be true
    end

    it "mutates class variable compound assignments" do
      muts = mutations_for("cvar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("@@total -= 1") }).to be true
    end

    it "mutates global variable compound assignments" do
      muts = mutations_for("gvar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("$counter -= 1") }).to be true
    end

    it "replaces &= with |= and ^=" do
      muts = mutations_for("bitwise_and_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x |= 0xFF") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("x ^= 0xFF") }).to be true
    end

    it "replaces |= with &=" do
      muts = mutations_for("bitwise_or_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x &= 0x01") }).to be true
    end

    it "replaces ^= with &=" do
      muts = mutations_for("bitwise_xor_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x &= 0x0F") }).to be true
    end

    it "replaces <<= with >>=" do
      muts = mutations_for("left_shift_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x >>= 2") }).to be true
    end

    it "replaces >>= with <<=" do
      muts = mutations_for("right_shift_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x <<= 2") }).to be true
    end

    it "generates correct number of mutations for &=" do
      muts = mutations_for("bitwise_and_assign")

      # 2 swaps (|, ^) + 1 removal = 3
      expect(muts.length).to eq(3)
    end

    it "replaces &&= with ||=" do
      muts = mutations_for("logical_and_assign")

      # 1 swap + 1 removal = 2
      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("x ||= true") }).to be true
    end

    it "replaces ||= with &&=" do
      muts = mutations_for("logical_or_assign")

      # 1 swap + 1 removal = 2
      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?('x &&= "default"') }).to be true
    end

    it "mutates instance variable &&=" do
      muts = mutations_for("ivar_logical_and_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("@flag ||= false") }).to be true
    end

    it "mutates instance variable ||=" do
      muts = mutations_for("ivar_logical_or_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?('@ivar_logical_or_assign &&= "unknown"') }).to be true
    end

    it "mutates class variable &&=" do
      muts = mutations_for("cvar_logical_and_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("@@flag ||= false") }).to be true
    end

    it "mutates class variable ||=" do
      muts = mutations_for("cvar_logical_or_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?('@@cvar_logical_or_assign &&= "unknown"') }).to be true
    end

    it "mutates global variable &&=" do
      muts = mutations_for("gvar_logical_and_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("$flag ||= false") }).to be true
    end

    it "mutates global variable ||=" do
      muts = mutations_for("gvar_logical_or_assign")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?('$gvar_logical_or_assign &&= "unknown"') }).to be true
    end

    it "generates removal mutation for arithmetic compound assignment" do
      muts = mutations_for("add_assign")

      removal = muts.find { |m| m.mutated_source.include?("def add_assign(x)\n    nil\n    x") }
      expect(removal).not_to be_nil
    end

    it "generates removal mutation for single-statement compound assignment" do
      muts = mutations_for("ivar_add_assign")

      removal = muts.find { |m| m.mutated_source.include?("def ivar_add_assign\n    nil\n  end") }
      expect(removal).not_to be_nil
    end

    it "generates removal mutation for logical compound assignment" do
      muts = mutations_for("logical_and_assign")

      removal = muts.find { |m| m.mutated_source.include?("def logical_and_assign(x)\n    nil\n    x") }
      expect(removal).not_to be_nil
    end

    it "includes removal in mutation count for +=" do
      muts = mutations_for("add_assign")

      # 2 swaps (-, *) + 1 removal = 3
      expect(muts.length).to eq(3)
    end

    it "does not mutate methods with no compound assignments" do
      muts = mutations_for("no_compound_assignment")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result).not_to be_failure,
                                "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("add_assign")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("compound_assignment")
      end
    end

    describe "operator writes on an attribute" do
      def mutated_lines(muts)
        muts.map { |m| m.mutated_slice.strip }
      end

      it "swaps the operator and nils the whole write" do
        expect(mutated_lines(mutations_for("attribute_add_assign")))
          .to contain_exactly("counter.total -= 1", "counter.total *= 1", "nil")
      end

      it "mutates a write that is one of several statements" do
        expect(mutated_lines(mutations_for("attribute_subtract_assign")))
          .to contain_exactly("account.balance += amount", "nil")
      end

      it "mutates a write on self" do
        expect(mutated_lines(mutations_for("self_attribute_shift_assign")))
          .to contain_exactly("self.flags >>= 1", "nil")
      end

      it "keeps the safe navigation of the write" do
        expect(mutated_lines(mutations_for("safe_attribute_multiply_assign")))
          .to contain_exactly("order&.quantity /= 2", "nil")
      end

      it "keeps the whole receiver chain" do
        expect(mutated_lines(mutations_for("chained_attribute_add_assign")))
          .to contain_exactly("order.totals.net -= 5", "order.totals.net *= 5", "nil")
      end

      it "descends past the write into a nested assignment" do
        # outer += : 2 swaps + 1 removal = 3, inner -= : 1 swap + 1 removal = 2
        expect(mutations_for("nested_attribute_op_write").length).to eq(5)
      end

      it "reports the mutation on the line of the write" do
        line = source.lines.index { |text| text.include?("account.balance -= amount") } + 1

        expect(mutations_for("attribute_subtract_assign").map(&:line).uniq).to eq([line])
      end

      it "leaves a plain attribute write alone" do
        expect(mutations_for("attribute_plain_write")).to be_empty
      end
    end

    describe "operator writes on an index" do
      def mutated_lines(muts)
        muts.map { |m| m.mutated_slice.strip }
      end

      it "swaps the operator and nils the whole write" do
        expect(mutated_lines(mutations_for("index_add_assign")))
          .to contain_exactly("counts[key] -= 1", "counts[key] *= 1", "nil")
      end

      it "mutates a write that is one of several statements" do
        expect(mutated_lines(mutations_for("index_subtract_assign")))
          .to contain_exactly("stock[sku] += amount", "nil")
      end

      it "mutates a write on self" do
        expect(mutated_lines(mutations_for("self_index_or_bits_assign")))
          .to contain_exactly("self[:flags] &= bit", "nil")
      end

      it "mutates a write inside a larger expression" do
        expect(mutated_lines(mutations_for("safe_index_multiply_assign")))
          .to contain_exactly("totals&.[](key) || (totals[key] /= 2)", "totals&.[](key) || (nil)")
      end

      it "keeps the whole receiver chain" do
        expect(mutated_lines(mutations_for("chained_index_add_assign")))
          .to contain_exactly("report.totals[key] -= 5", "report.totals[key] *= 5", "nil")
      end

      it "keeps every index of a write with several" do
        expect(mutated_lines(mutations_for("multiple_index_add_assign")))
          .to contain_exactly("matrix[row, column] -= 1", "matrix[row, column] *= 1", "nil")
      end

      it "descends past the write into an assignment nested in its value" do
        # outer += : 2 swaps + 1 removal = 3, inner -= : 1 swap + 1 removal = 2
        expect(mutations_for("nested_index_op_write").length).to eq(5)
      end

      it "descends past the write into an assignment nested in its index" do
        expect(mutations_for("nested_index_key_op_write").length).to eq(5)
      end

      it "reports the mutation on the line of the write" do
        line = source.lines.index { |text| text.include?("stock[sku] -= amount") } + 1

        expect(mutations_for("index_subtract_assign").map(&:line).uniq).to eq([line])
      end

      it "leaves a plain index write alone" do
        expect(mutations_for("index_plain_write")).to be_empty
      end
    end

    describe "operator writes on a constant" do
      def constant_subjects(name)
        subjects_from_fixture.select { |s| s.kind == :constant_write && s.name == "CompoundAssignment::#{name}" }
      end

      def mutated_lines(muts)
        muts.map { |m| m.mutated_slice.strip }
      end

      it "runs on constant-write subjects as well as the default kinds" do
        expect(described_class.subject_kinds).to eq(%i[method scope aasm callback constant_write])
      end

      it "swaps the operator and nils the whole write" do
        _assignment, bump, = constant_subjects("CONST_TOTAL")

        expect(mutated_lines(described_class.new.call(bump)))
          .to contain_exactly("CONST_TOTAL -= 2", "CONST_TOTAL *= 2", "nil")
      end

      it "leaves the constant's plain assignment alone" do
        assignment, = constant_subjects("CONST_TOTAL")

        expect(described_class.new.call(assignment)).to be_empty
      end

      it "mutates an operator write on a constant path" do
        path_write = constant_subjects("CONST_TOTAL").find { |s| s.source == "CompoundAssignment::CONST_TOTAL -= 3" }

        expect(mutated_lines(described_class.new.call(path_write)))
          .to contain_exactly("CompoundAssignment::CONST_TOTAL += 3", "nil")
      end

      it "descends past a constant path write into a nested assignment" do
        path_write = constant_subjects("CONST_FLAGS").last

        # outer ^= : 1 swap + 1 removal = 2, inner <<= : 1 swap + 1 removal = 2
        expect(described_class.new.call(path_write).length).to eq(4)
      end

      it "descends past the write into a nested assignment" do
        flags = constant_subjects("CONST_FLAGS").find { |s| s.source == "CONST_FLAGS |= (CONST_TOTAL -= 1)" }

        expect(mutated_lines(described_class.new.call(flags))).to contain_exactly(
          "CONST_FLAGS &= (CONST_TOTAL -= 1)", "nil", "CONST_FLAGS |= (CONST_TOTAL += 1)", "CONST_FLAGS |= (nil)"
        )
      end

      it "mutates a compound assignment in a lambda assigned to a constant" do
        handler, = constant_subjects("CONST_HANDLER")

        expect(mutated_lines(described_class.new.call(handler))).to contain_exactly(
          "CONST_HANDLER = ->(count) { count -= 1 }", "CONST_HANDLER = ->(count) { count *= 1 }",
          "CONST_HANDLER = ->(count) { nil }"
        )
      end
    end

    describe "recursion into nested compound assignments" do
      # Each nested fixture wraps an inner `t -= 1` (a local-variable
      # operator-write yielding 2 mutations) inside an outer compound
      # assignment of a specific node type. The operator must descend past
      # the outer write to also mutate the inner one — so dropping the outer
      # visit method's `super` is observable as a smaller mutation count.

      it "descends past a local-variable operator-write into a nested assignment" do
        muts = mutations_for("nested_lvar_op_write")

        # outer += : 2 swaps + 1 removal = 3, inner -= : 1 swap + 1 removal = 2
        expect(muts.length).to eq(5)
      end

      it "descends past an instance-variable operator-write into a nested assignment" do
        muts = mutations_for("nested_ivar_op_write")

        expect(muts.length).to eq(5)
      end

      it "descends past a class-variable operator-write into a nested assignment" do
        muts = mutations_for("nested_cvar_op_write")

        expect(muts.length).to eq(5)
      end

      it "descends past a global-variable operator-write into a nested assignment" do
        muts = mutations_for("nested_gvar_op_write")

        expect(muts.length).to eq(5)
      end

      it "descends past a local-variable and-write into a nested assignment" do
        muts = mutations_for("nested_lvar_and_write")

        # outer &&= : 1 swap + 1 removal = 2, inner -= : 2
        expect(muts.length).to eq(4)
      end

      it "descends past a local-variable or-write into a nested assignment" do
        muts = mutations_for("nested_lvar_or_write")

        expect(muts.length).to eq(4)
      end

      it "descends past an instance-variable and-write into a nested assignment" do
        muts = mutations_for("nested_ivar_and_write")

        expect(muts.length).to eq(4)
      end

      it "descends past an instance-variable or-write into a nested assignment" do
        muts = mutations_for("nested_ivar_or_write")

        expect(muts.length).to eq(4)
      end

      it "descends past a class-variable and-write into a nested assignment" do
        muts = mutations_for("nested_cvar_and_write")

        expect(muts.length).to eq(4)
      end

      it "descends past a class-variable or-write into a nested assignment" do
        muts = mutations_for("nested_cvar_or_write")

        expect(muts.length).to eq(4)
      end

      it "descends past a global-variable and-write into a nested assignment" do
        muts = mutations_for("nested_gvar_and_write")

        expect(muts.length).to eq(4)
      end

      it "descends past a global-variable or-write into a nested assignment" do
        muts = mutations_for("nested_gvar_or_write")

        expect(muts.length).to eq(4)
      end
    end
  end
end
