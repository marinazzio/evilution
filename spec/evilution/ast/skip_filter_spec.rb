# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_filter"

RSpec.describe Evilution::AST::SkipFilter do
  around do |example|
    Evilution::AST::ParseCache.clear!
    example.run
    Evilution::AST::ParseCache.clear!
  end

  def config(**overrides)
    Evilution::Config.new(skip_config_file: true, **overrides)
  end

  def node_at(source, slice, type)
    pending = [Prism.parse(source).value]
    until pending.empty?
      node = pending.pop
      return node if node.is_a?(type) && node.slice == slice

      pending.concat(node.compact_child_nodes)
    end
  end

  let(:source) { "def f(x)\n  logger.info(\"saving\")\n  raise Error, \"bad\" if x\n  x + 1\nend\n" }
  let(:log_text) { node_at(source, "\"saving\"", Prism::StringNode) }
  let(:raise_text) { node_at(source, "\"bad\"", Prism::StringNode) }
  let(:sum) { node_at(source, "x + 1", Prism::CallNode) }
  let(:made) { Struct.new(:file_path, :mutated_source) }

  describe ".for" do
    it "is nil when neither ignore_patterns nor skip_sites is set" do
      expect(described_class.for(config)).to be_nil
    end

    it "builds a filter for ignore_patterns alone" do
      expect(described_class.for(config(ignore_patterns: ["call{name=info}"]))).to be_a(described_class)
    end

    it "builds a filter for skip_sites alone" do
      expect(described_class.for(config(skip_sites: [:logging]))).to be_a(described_class)
    end
  end

  describe "#skip?" do
    let(:filter) { described_class.new(patterns: [], sites: %i[logging error_messages]) }

    it "skips a mutation inside a site of a chosen preset" do
      expect(filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")).to be true
      expect(filter.skip?(raise_text, file_path: "a.rb", source: source, mutated_source: "m2")).to be true
    end

    it "keeps a mutation outside every site" do
      expect(filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")).to be false
    end

    it "keeps a mutation inside a site of a preset not chosen" do
      filter = described_class.new(patterns: [], sites: [:logging])

      expect(filter.skip?(raise_text, file_path: "a.rb", source: source, mutated_source: "m1")).to be false
    end

    it "skips a mutation an ignore pattern matches" do
      filter = described_class.new(patterns: ["call{name=+}"], sites: [])

      expect(filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")).to be true
    end

    it "skips a mutation whose ancestor an ignore pattern matches" do
      filter = described_class.new(patterns: ["def{name=f}"], sites: [])

      expect(filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")).to be true
    end

    it "tests the node alone when no source is given" do
      expect(filter.skip?(log_text)).to be false
    end
  end

  describe "#skipped_count and #skipped_by_site" do
    let(:filter) { described_class.new(patterns: ["call{name=+}"], sites: %i[logging error_messages]) }

    it "counts every skip, and the site skips per preset" do
      filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")
      filter.skip?(raise_text, file_path: "a.rb", source: source, mutated_source: "m2")
      filter.skip?(raise_text, file_path: "a.rb", source: source, mutated_source: "m3")
      filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m4")

      expect(filter.skipped_count).to eq(4)
      expect(filter.skipped_by_site).to eq(logging: 1, error_messages: 2)
    end

    it "counts a mutation made twice once" do
      2.times { filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1") }

      expect(filter.skipped_count).to eq(1)
      expect(filter.skipped_by_site).to eq(logging: 1)
    end

    it "attributes a mutation to the first reason that skipped it" do
      filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")
      filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")

      expect(filter.skipped_count).to eq(1)
      expect(filter.skipped_by_site).to eq({})
    end

    it "leaves out a skipped mutation the run makes all the same from another node" do
      filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")
      filter.skip?(raise_text, file_path: "a.rb", source: source, mutated_source: "m2")

      expect(filter.skipped_count(made: [made.new("a.rb", "m1")])).to eq(1)
      expect(filter.skipped_by_site(made: [made.new("a.rb", "m1")])).to eq(error_messages: 1)
    end

    it "counts the same mutated source of another file apart" do
      filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")
      filter.skip?(log_text, file_path: "b.rb", source: source, mutated_source: "m1")

      expect(filter.skipped_by_site(made: [made.new("b.rb", "m1")])).to eq(logging: 1)
    end

    it "counts every skip when no mutated source is given" do
      2.times { filter.skip?(log_text, file_path: "a.rb", source: source) }

      expect(filter.skipped_by_site).to eq(logging: 2)
    end

    it "starts counting afresh after a reset" do
      filter.skip?(log_text, file_path: "a.rb", source: source, mutated_source: "m1")
      filter.reset_count!

      expect(filter.skipped_count).to eq(0)
      expect(filter.skipped_by_site).to eq({})
    end
  end

  it "builds one parent index per source for the patterns and the presets together" do
    filter = described_class.new(patterns: ["call{name=validates}"], sites: [:logging])
    allow(Evilution::AST::ParentIndex).to receive(:new).and_call_original

    filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")

    expect(Evilution::AST::ParentIndex).to have_received(:new).once
  end

  it "does not look up ancestors when no preset is chosen and no pattern matches the node" do
    filter = described_class.new(patterns: [], sites: [])
    allow(Evilution::AST::ParentIndex).to receive(:new).and_call_original

    expect(filter.skip?(sum, file_path: "a.rb", source: source, mutated_source: "m1")).to be false
    expect(Evilution::AST::ParentIndex).not_to have_received(:new)
  end
end
