# frozen_string_literal: true

require "tmpdir"
require "evilution/integration/rspec"

RSpec.describe Evilution::Integration::RSpec::TargetResolver do
  # Regression for EV-wqxu / GH #1278: when a worker is chdir'd into a per-
  # mutation sandbox, RSpec::Core::Runner cannot find a CWD-relative spec
  # path. #resolve re-anchors such paths to Evilution::PROJECT_ROOT
  # only when the isolated-worker flag is set, and only when the original
  # path does not already resolve under the current CWD.
  describe "#resolve (isolated-worker path anchoring)" do
    subject(:resolver) { described_class.new }

    around do |example|
      previous = Evilution.instance_variable_get(:@in_isolated_worker)
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, previous)
    end

    def resolve(target)
      resolver.resolve(target)
    end

    let(:project_relative_spec) { "spec/evilution/integration/rspec_spec.rb" }

    it "returns absolute targets unchanged" do
      Evilution.in_isolated_worker!
      absolute = File.expand_path(project_relative_spec, Evilution::PROJECT_ROOT)

      expect(resolve(absolute)).to eq(absolute)
      expect(resolve("#{absolute}:42")).to eq("#{absolute}:42")
    end

    it "returns CWD-resolvable targets unchanged (no rewrite when CWD finds the file)" do
      Evilution.in_isolated_worker!

      Dir.chdir(Evilution::PROJECT_ROOT) do
        expect(resolve(project_relative_spec)).to eq(project_relative_spec)
        expect(resolve("#{project_relative_spec}:7")).to eq("#{project_relative_spec}:7")
      end
    end

    it "leaves targets untouched when the isolated-worker flag is not set" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(resolve(project_relative_spec)).to eq(project_relative_spec)
          expect(resolve("#{project_relative_spec}:9")).to eq("#{project_relative_spec}:9")
        end
      end
    end

    it "expands against PROJECT_ROOT when flagged and the CWD lookup fails" do
      Evilution.in_isolated_worker!
      absolute = File.expand_path(project_relative_spec, Evilution::PROJECT_ROOT)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(resolve(project_relative_spec)).to eq(absolute)
        end
      end
    end

    it "preserves a `:LINE` suffix when expanding against PROJECT_ROOT" do
      Evilution.in_isolated_worker!
      absolute = File.expand_path(project_relative_spec, Evilution::PROJECT_ROOT)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(resolve("#{project_relative_spec}:7")).to eq("#{absolute}:7")
        end
      end
    end

    it "preserves a multi-segment `:LINE:LINE` suffix when expanding" do
      Evilution.in_isolated_worker!
      absolute = File.expand_path(project_relative_spec, Evilution::PROJECT_ROOT)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(resolve("#{project_relative_spec}:7:9")).to eq("#{absolute}:7:9")
        end
      end
    end

    it "splits the line suffix at the END of the string so colons inside the path are preserved" do
      Evilution.in_isolated_worker!
      colon_path = "tmp/has:colon/foo_spec.rb"
      absolute_colon_target = "/abs#{colon_path}:42"

      # Absolute already → returned as-is, but verify the split logic itself
      # via a path that does not exist anywhere — falls through to
      # `return target` after the PROJECT_ROOT lookup misses.
      expect(resolve(absolute_colon_target)).to eq(absolute_colon_target)
      expect(resolve("#{colon_path}:42")).to eq("#{colon_path}:42")
    end

    it "leaves a target untouched when neither CWD nor PROJECT_ROOT can resolve it" do
      Evilution.in_isolated_worker!
      missing = "spec/definitely_does_not_exist_#{rand(1_000_000)}.rb"

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(resolve(missing)).to eq(missing)
          expect(resolve("#{missing}:5")).to eq("#{missing}:5")
        end
      end
    end
  end

  describe "#call" do
    it "resolves every target" do
      expect(described_class.new.call(["/abs/a_spec.rb", "/abs/b_spec.rb:3"])).to eq(["/abs/a_spec.rb", "/abs/b_spec.rb:3"])
    end
  end
end
