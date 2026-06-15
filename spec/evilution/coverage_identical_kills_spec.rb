# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "evilution/ast/parser"
require "evilution/mutator"
require "evilution/isolation/fork"
require "evilution/integration/rspec"
require "evilution/example_filter"
require "evilution/spec_ast_cache"
require "evilution/coverage/map_builder"
require "evilution/coverage_example_filter"

# EV-lqqk accuracy gate (in-suite): coverage-based targeting must never lose a
# kill the full-file run would catch. Build a real per-example coverage map for a
# fixture, then run every real mutation twice -- once with the CoverageExampleFilter
# selecting only the covering examples, once full-file (no filter) -- and assert
# the set of KILLED mutations is identical.
#
# Lives at the top level (not under spec/evilution/integration/) so it loads
# before the integration suite's global RSpec.world reset.
RSpec.describe "Coverage targeting: identical kills vs full-file" do
  let(:project) { Dir.mktmpdir("evilution_idk") }
  let(:lib_dir) { File.join(project, "lib") }
  let(:spec_dir) { File.join(project, "spec") }
  let(:source_path) { File.join(lib_dir, "idk_calc.rb") }
  let(:spec_path) { File.join(spec_dir, "idk_calc_spec.rb") }

  let(:source) do
    <<~RUBY
      class IdkCalc
        def add(a, b)
          a + b
        end

        def sub(a, b)
          a - b
        end
      end
    RUBY
  end

  before do
    FileUtils.mkdir_p(lib_dir)
    FileUtils.mkdir_p(spec_dir)
    File.write(source_path, source)
    File.write(spec_path, <<~RUBY)
      require_relative "#{source_path}"

      RSpec.describe IdkCalc do
        it "adds" do
          expect(described_class.new.add(2, 3)).to eq(5)
        end

        it "subtracts" do
          expect(described_class.new.sub(5, 2)).to eq(3)
        end
      end
    RUBY
  end

  after { FileUtils.rm_rf(project) }

  def real_mutations
    subjects = Evilution::AST::Parser.new.call(source_path)
    registry = Evilution::Mutator::Registry.default
    subjects.flat_map { |subject| registry.mutations_for(subject) }
  end

  def killed_status(mutation, integration)
    isolator = Evilution::Isolation::Fork.new
    result = isolator.call(
      mutation: mutation,
      test_command: ->(mut) { integration.call(mut) },
      timeout: 20
    )
    result.status == :killed
  end

  it "kills exactly the same mutations under coverage targeting as under full-file" do
    mutations = real_mutations
    expect(mutations).not_to be_empty

    map = Evilution::Coverage::MapBuilder.new(spec_files: [spec_path], target_files: [source_path]).call
    expect(map.built?(source_path)).to be(true)

    lexical = Evilution::ExampleFilter.new(cache: Evilution::SpecAstCache.new)
    coverage_filter = Evilution::CoverageExampleFilter.new(map: map, lexical: lexical)

    coverage_integration = Evilution::Integration::RSpec.new(test_files: [spec_path], example_filter: coverage_filter)
    full_integration = Evilution::Integration::RSpec.new(test_files: [spec_path])

    killed_by_coverage = mutations.select { |m| killed_status(m, coverage_integration) }.map(&:to_s)
    killed_by_full = mutations.select { |m| killed_status(m, full_integration) }.map(&:to_s)

    expect(killed_by_coverage).to match_array(killed_by_full)
    expect(killed_by_full).not_to be_empty # the fixture genuinely has killable mutations
  end
end
