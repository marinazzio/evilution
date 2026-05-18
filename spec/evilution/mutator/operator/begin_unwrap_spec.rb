# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Mutator::Operator::BeginUnwrap do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/begin_unwrap.rb", __dir__) }
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

  def mutations_from_source(src)
    tmpfile = Tempfile.new(["begin_unwrap", ".rb"])
    tmpfile.write(src)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "#call" do
    it "unwraps simple begin/end" do
      muts = mutations_for("simple_begin")

      expect(muts.length).to eq(1)
      expect(muts.first.diff).to include("- ")
      expect(muts.first.diff).to include("begin")
    end

    it "unwraps multiline begin/end" do
      muts = mutations_for("multiline_begin")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("setup")
      expect(muts.first.mutated_source).to include("process")
      expect(muts.first.mutated_source).to include("cleanup")
    end

    it "skips begin with rescue" do
      muts = mutations_for("begin_with_rescue")

      expect(muts).to be_empty
    end

    it "skips begin with ensure" do
      muts = mutations_for("begin_with_ensure")

      expect(muts).to be_empty
    end

    it "skips methods without begin" do
      muts = mutations_for("no_begin")

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
      muts = mutations_for("simple_begin")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("begin_unwrap")
      end
    end

    it "still visits a nested begin inside a non-unwrappable begin" do
      src = <<~RUBY
        def outer
          begin
            begin
              inner_work
            end
          rescue StandardError
            fallback
          end
        end
      RUBY

      muts = mutations_from_source(src)

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("inner_work")
    end

    it "visits a nested begin inside an unwrappable begin" do
      src = <<~RUBY
        def outer
          begin
            begin
              inner_work
            end
          end
        end
      RUBY

      muts = mutations_from_source(src)

      expect(muts.length).to eq(2)
    end

    it "produces no mutation for an empty begin/end and does not raise" do
      src = <<~RUBY
        def empty
          begin
          end
        end
      RUBY

      expect { mutations_from_source(src) }.not_to raise_error
      expect(mutations_from_source(src)).to be_empty
    end
  end
end
