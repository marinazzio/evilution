# frozen_string_literal: true

RSpec.describe Evilution::Mutator::ConstantValueSubjects do
  let(:operator) do
    Class.new(Evilution::Mutator::Base) do
      extend Evilution::Mutator::ConstantValueSubjects

      def visit_integer_node(node)
        add_mutation(offset: node.location.start_offset, length: node.location.length, replacement: "0", node: node)
      end
    end
  end

  def subjects_of(source)
    Tempfile.create(["constant_value_subjects", ".rb"]) do |file|
      file.write(source)
      file.flush
      yield Evilution::AST::Parser.new.call(file.path)
    end
  end

  it "adds constant-write subjects to the operator's kinds" do
    expect(operator.subject_kinds).to eq(%i[method scope aasm callback constant_write])
  end

  it "gives the operator the constant-value visits" do
    expect(operator).to include(described_class::Visits)
  end

  it "keeps the visit helpers private" do
    expect(described_class::Visits.private_instance_methods(false)).to contain_exactly(:constant_value?, :constant_value_freeze?)
  end

  it "skips a method defined in a constant's value, which is a subject of its own" do
    subjects_of("class C\n  H = Class.new do\n    SIZE = 1\n    def go = 2\n  end\nend\n") do |subjects|
      handler = subjects.find { |s| s.name == "C::H" }

      expect(operator.new.call(handler).map { |m| m.mutated_slice.strip }).to eq(["SIZE = 0"])
    end
  end

  it "visits the method through its own subject" do
    subjects_of("class C\n  H = Class.new do\n    def go = 2\n  end\nend\n") do |subjects|
      go = subjects.find { |s| s.kind == :method }

      expect(operator.new.call(go).map { |m| m.mutated_slice.strip }).to eq(["def go = 0"])
    end
  end
end
