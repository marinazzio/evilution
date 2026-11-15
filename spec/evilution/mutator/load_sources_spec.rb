# frozen_string_literal: true

require "tempfile"
require "evilution/mutator/load_sources"
require "evilution/ast/def_region"
require "evilution/ast/source_surgeon"
require "evilution/integration/loading/body_call_neutralizer"

RSpec.describe Evilution::Mutator::LoadSources do
  let(:source) { "class Order\n  has_many :lines\n\n  def total\n    1\n  end\nend\n" }
  let(:tmpfile) do
    file = Tempfile.new(["order", ".rb"])
    file.write(source)
    file.close
    file
  end
  let(:def_node) { Prism.parse(source).value.statements.body.first.body.body.last }
  let(:neutralizer) { Evilution::Integration::Loading::BodyCallNeutralizer.new }
  let(:offset) { source.index("1\n  end") }
  let(:mutated) { Evilution::AST::SourceSurgeon.splice(source, offset: offset, length: 1, replacement: "2") }
  let(:region) { Evilution::AST::DefRegion.new(source, def_node).parse(offset: offset, length: 1, replacement: "2") }

  def subject_of(kind, concern_hook: false)
    Evilution::Subject.new(name: "Order#total", file_path: tmpfile.path, line_number: 4,
                           source: def_node.slice, node: def_node, kind: kind, concern_hook: concern_hook)
  end

  def load_sources(kind = :method, concern_hook: false)
    described_class.new(subject_of(kind, concern_hook: concern_hook), source, neutralizer)
  end

  def kept(offset)
    { keep_offset: offset, keep_lines: 4..6, keep_source: def_node.slice }
  end

  before do
    Evilution::Integration::Loading::BodyCallNeutralizer.preloaded_features = Set[File.expand_path(tmpfile.path)]
    Evilution::Mutator::RestoreSourceCache.clear!
  end

  after do
    Evilution::Integration::Loading::BodyCallNeutralizer.reset_preload_snapshot!
    Evilution::Mutator::RestoreSourceCache.clear!
    tmpfile.unlink
  end

  describe "#eval_source" do
    let(:neutralized_mutation) { "class Order\n  ()\n\n  def total\n    2\n  end\nend\n" }

    it "is the mutated source as it is when it does not parse" do
      surgery = Evilution::AST::SourceSurgeon::Result.new(source: "def (\n", status: :unparseable)

      expect(load_sources.eval_source(surgery, offset)).to eq("def (\n")
    end

    it "carries the mutation into the neutralized file when the method alone was parsed for it" do
      surgery = Evilution::AST::SourceSurgeon.check(mutated) { region }
      allow(neutralizer).to receive(:call).and_call_original

      expect(load_sources.eval_source(surgery, offset)).to eq(neutralized_mutation)
      expect(neutralizer).not_to have_received(:call)
    end

    it "neutralizes the mutated file when the whole file was parsed for it" do
      surgery = Evilution::AST::SourceSurgeon.check(mutated)

      expect(load_sources.eval_source(surgery, offset)).to eq(neutralized_mutation)
    end

    %i[scope aasm callback].each do |kind|
      it "neutralizes the mutated file for a #{kind} subject, keeping its declaration" do
        surgery = Evilution::AST::SourceSurgeon.check(mutated) { region }
        allow(neutralizer).to receive(:call).and_call_original

        load_sources(kind).eval_source(surgery, offset)

        expect(neutralizer).to have_received(:call).with(mutated, file_path: tmpfile.path, **kept(offset))
      end
    end

    it "neutralizes the mutated file, keeping the declaration, for a subject written in a concern's hook block" do
      surgery = Evilution::AST::SourceSurgeon.check(mutated) { region }
      allow(neutralizer).to receive(:call).and_call_original

      load_sources(:method, concern_hook: true).eval_source(surgery, offset)

      expect(neutralizer).to have_received(:call).with(mutated, file_path: tmpfile.path, **kept(offset))
    end

    it "neutralizes the whole mutated file of a method subject, keeping nothing" do
      surgery = Evilution::AST::SourceSurgeon.check(mutated)
      allow(neutralizer).to receive(:call).and_call_original

      load_sources.eval_source(surgery, offset)

      expect(neutralizer).to have_received(:call).with(mutated, file_path: tmpfile.path)
    end

    it "neutralizes the mutated file when the mutated method holds a class body" do
      body = "class << self\n      foo 1\n    end"
      with_class = Evilution::AST::SourceSurgeon.splice(source, offset: offset, length: 1, replacement: body)
      class_region = Evilution::AST::DefRegion.new(source, def_node).parse(offset: offset, length: 1, replacement: body)
      surgery = Evilution::AST::SourceSurgeon.check(with_class) { class_region }

      expect(load_sources.eval_source(surgery, offset)).to include("class << self\n      ()\n")
    end

    it "carries a mutation into a file the parent never loaded as the mutated file itself" do
      Evilution::Integration::Loading::BodyCallNeutralizer.preloaded_features = Set.new
      surgery = Evilution::AST::SourceSurgeon.check(mutated) { region }

      expect(load_sources.eval_source(surgery, offset)).to equal(mutated)
    end
  end

  describe "#restore_source" do
    it "is the file neutralized, shared by the mutations of the file" do
      restore = load_sources.restore_source(offset)

      expect(restore).to eq("class Order\n  ()\n\n  def total\n    1\n  end\nend\n")
      expect(load_sources.restore_source(offset)).to equal(restore)
    end

    it "is the file neutralized keeping the declaration of a subject whose declaration is kept" do
      allow(neutralizer).to receive(:call).and_call_original

      restore = load_sources(:scope).restore_source(offset)

      expect(neutralizer).to have_received(:call).with(source, file_path: tmpfile.path, **kept(offset))
      expect(restore).to eq("class Order\n  ()\n\n  def total\n    1\n  end\nend\n")
    end
  end
end
