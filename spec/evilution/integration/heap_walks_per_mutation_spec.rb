# frozen_string_literal: true

require "tmpdir"
require "active_support"
require "active_support/concern"
require "rspec/core"
require "evilution/integration/rspec"

# Counts the walks of the heap (ObjectSpace.each_object) one mutation costs,
# from applying it through its test run to restoring the file, under both
# isolations. Each walk touches every object in the process; in a forked
# mutation process every page it shares with its parent has to be mapped
# again. A Rails application holds millions of objects, so the walks used to
# be most of a mutation's overhead.
#
# The mutation is the worst case for the load pipeline: it changes a
# declaration in a concern's `included` block, so applying it clears the
# concern's state and re-declares the block on the classes that include the
# concern, and the file creates an anonymous module of its own.
RSpec.describe "Heap walks per mutation" do
  original = <<~RUBY
    module EvilutionHeapWalkConcern
      extend ActiveSupport::Concern

      included do
        def self.label = :original
      end
    end

    class EvilutionHeapWalkModel
      include EvilutionHeapWalkConcern
    end

    EvilutionHeapWalkModel.extend(Module.new { def extended_by_file = :original })
  RUBY

  redeclaration = "::Evilution::Integration::Loading::ConcernRedeclaration"
  mutated = original.gsub(":original", ":mutated")
                    .sub("  end\nend", "  end; #{redeclaration}.call(self)\nend")

  around do |example|
    Dir.mktmpdir("evilution_heap_walks") do |dir|
      @file_path = File.join(dir, "heap_walk_concern.rb")
      File.write(@file_path, original)
      load(@file_path)
      example.run
    end
  ensure
    %i[EvilutionHeapWalkModel EvilutionHeapWalkConcern].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end

  around do |example|
    previous = Evilution.instance_variable_get(:@single_mutation_process)
    example.run
  ensure
    Evilution.instance_variable_set(:@single_mutation_process, previous)
  end

  let(:mutation) do
    Struct.new(:file_path, :original_source, :mutated_source, :eval_source, :restore_source, keyword_init: true)
          .new(file_path: @file_path, original_source: original, mutated_source: mutated,
               eval_source: mutated, restore_source: original)
  end
  let(:labels_seen) { [] }
  let(:integration) do
    Evilution::Integration::RSpec.new(test_files: [@file_path]).tap do |built|
      allow(built).to receive(:reset_examples)
    end
  end

  before do
    allow(RSpec.configuration).to receive(:add_formatter)
    seen = labels_seen
    allow(RSpec::Core::Runner).to receive(:run) do
      seen << EvilutionHeapWalkModel.label
      0
    end
  end

  def walks_for(mutation)
    walks = 0
    each_object = ObjectSpace.method(:each_object)
    allow(ObjectSpace).to receive(:each_object) do |*args, &block|
      walks += 1
      each_object.call(*args, &block)
    end
    integration.call(mutation)
    walks
  end

  context "when the run has warmed the loading state in the parent" do
    before { integration.warm_loading }

    it "walks the heap no time in a forked mutation process" do
      Evilution.single_mutation_process!

      expect(walks_for(mutation)).to eq(0)
      expect(labels_seen).to eq([:mutated])
    end

    it "walks the heap no time under in-process isolation, the restore included" do
      Evilution.instance_variable_set(:@single_mutation_process, false)

      expect(walks_for(mutation)).to eq(0)
      expect(labels_seen).to eq([:mutated])
    end
  end

  # ActiveSupport may be loaded only once the process is running mutations:
  # without a preload, by the tests themselves.
  context "when nothing was warmed" do
    before do
      allow(Evilution::Integration::Loading::ConcernRegistry).to receive(:default)
        .and_return(Evilution::Integration::Loading::ConcernRegistry.new)
    end

    it "walks the heap at most once in a forked mutation process" do
      Evilution.single_mutation_process!

      expect(walks_for(mutation)).to be <= 1
      expect(labels_seen).to eq([:mutated])
    end

    it "walks the heap at most once under in-process isolation" do
      Evilution.instance_variable_set(:@single_mutation_process, false)

      expect(walks_for(mutation)).to be <= 1
      expect(labels_seen).to eq([:mutated])
    end
  end
end
