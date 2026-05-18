# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockParamRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/block_param_removal.rb", __dir__) }
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
    it "removes block param when it is the only parameter" do
      muts = mutations_for("only_block_param")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def only_block_param\n")
    end

    it "removes block param while keeping other parameters" do
      muts = mutations_for("with_other_params")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def with_other_params(a, b)\n")
    end

    it "removes block param with keyword parameters" do
      muts = mutations_for("with_keyword_and_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def with_keyword_and_block(name:)\n")
    end

    it "skips methods without block param" do
      muts = mutations_for("no_block_param")

      expect(muts).to be_empty
    end

    it "skips methods without parameters" do
      muts = mutations_for("no_params")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("only_block_param")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("block_param_removal")
      end
    end

    describe "recursion into nested defs" do
      it "descends into a nested def when the outer def has no parameters" do
        muts = mutations_for("no_params_outer")

        expect(muts.length).to eq(1)
        expect(muts.first.diff).to include("def no_params_inner(&blk)")
        expect(muts.first.diff).to include("+     def no_params_inner")
      end

      it "descends into a nested def when the outer def has no block parameter" do
        muts = mutations_for("plain_params_outer")

        expect(muts.length).to eq(1)
        expect(muts.first.diff).to include("def plain_params_inner(&blk)")
      end

      it "descends into a nested def when the outer def is an anonymous-forward def" do
        muts = mutations_for("anon_forward_outer")

        expect(muts.length).to eq(1)
        expect(muts.first.diff).to include("def anon_forward_inner(&blk)")
      end

      it "removes the outer block param and still descends into a nested def" do
        muts = mutations_for("block_param_outer")

        expect(muts.length).to eq(2)
        diffs = muts.map(&:diff)
        expect(diffs.any? { |d| d.include?("def block_param_outer(&outer_blk)") }).to be true
        expect(diffs.any? { |d| d.include?("def block_param_inner(&inner_blk)") }).to be true
      end
    end

    describe "params with optional and block parameters" do
      it "removes only the block param, keeping the optional parameter" do
        muts = mutations_for("optional_and_block")

        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("def optional_and_block(value = 1)\n")
        expect(muts.first.mutated_source).not_to include("def optional_and_block\n")
      end
    end

    describe "anonymous block param with an empty body" do
      it "does not crash and removes the anonymous block param" do
        expect { mutations_for("anon_block_empty_body") }.not_to raise_error

        muts = mutations_for("anon_block_empty_body")
        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("def anon_block_empty_body\n")
      end
    end

    describe "anonymous block-forward safety" do
      it "skips def with anonymous `&` param when body forwards `&`" do
        # def f(input, &) = helper(map(input), &)
        # Removing the `&` from the signature would leave the orphan `&` in the body,
        # producing unparseable Ruby.
        muts = mutations_for("anon_block_forwarded")

        expect(muts).to be_empty
      end

      it "still removes anonymous `&` param when body does not forward it" do
        # def f(input, &) = input * 2
        # Body has no `&` forward; the mutation is safe.
        muts = mutations_for("anon_block_unused")

        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("def anon_block_unused(input)\n")
        expect(muts.first.parse_status).to eq(:ok)
      end

      it "still removes named `&block` param even when body forwards it (NameError, not parse error)" do
        # def f(input, &block) = helper(input, &block)
        # Named block removal produces NameError at runtime but still parses.
        # That is a useful (kill-able) mutation, so allow it.
        muts = mutations_for("named_block_referenced")

        expect(muts.length).to eq(1)
        expect(muts.first.parse_status).to eq(:ok)
      end

      it "does not treat a nested def's `&` forward as the outer def's" do
        # def outer(&)
        #   def inner(&)
        #     g(&)
        #   end
        # end
        # The `&` in `g(&)` belongs to `inner`, not `outer`. Removing `outer`'s
        # unused `&` remains parseable, so the mutation must NOT be skipped.
        muts = mutations_for("anon_block_with_nested_def")

        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("def anon_block_with_nested_def(input)\n")
        expect(muts.first.parse_status).to eq(:ok)
      end
    end
  end
end
