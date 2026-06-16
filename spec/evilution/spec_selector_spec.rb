# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "pathname"
require "evilution/spec_selector"

RSpec.describe Evilution::SpecSelector do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def create_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  def build(spec_files: [], spec_mappings: {}, spec_pattern: nil)
    described_class.new(
      spec_files: spec_files,
      spec_mappings: spec_mappings,
      spec_pattern: spec_pattern
    )
  end

  describe "#call precedence" do
    it "returns spec_files for any source when spec_files is non-empty" do
      selector = build(spec_files: ["spec/explicit_spec.rb"])

      expect(selector.call("app/anything.rb")).to eq(["spec/explicit_spec.rb"])
    end

    it "returns spec_mappings entries when present and existing" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: {
                         "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"]
                       })

      expect(selector.call("app/controllers/games_controller.rb")).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "filters mappings to only existing files" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: {
                         "app/controllers/games_controller.rb" => [
                           "spec/requests/games_overlay_spec.rb",
                           "spec/requests/missing_spec.rb"
                         ]
                       })

      expect(selector.call("app/controllers/games_controller.rb")).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "falls through to default resolver when mapping entries all missing" do
      create_file("spec/foo_spec.rb")
      selector = build(spec_mappings: { "lib/foo.rb" => ["spec/missing_spec.rb"] })

      expect(selector.call("lib/foo.rb")).to eq(["spec/foo_spec.rb"])
    end

    it "uses default resolver when no mapping for source" do
      create_file("spec/foo_spec.rb")
      selector = build

      expect(selector.call("lib/foo.rb")).to eq(["spec/foo_spec.rb"])
    end

    it "applies spec_pattern to default resolver candidates" do
      create_file("spec/requests/foo_spec.rb")
      create_file("spec/controllers/foo_controller_spec.rb")
      selector = build(spec_pattern: "spec/controllers/**/*_spec.rb")

      expect(selector.call("app/controllers/foo_controller.rb"))
        .to eq(["spec/controllers/foo_controller_spec.rb"])
    end

    it "returns nil when default resolver finds no match" do
      selector = build

      expect(selector.call("lib/missing.rb")).to be_nil
    end

    it "expands a dir-grouped test directory into its files via the resolver" do
      create_file("test/unit/branch/branch_test.rb")
      create_file("test/unit/branch/conflict_test.rb")
      selector = described_class.new(
        spec_resolver: Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb")
      )

      expect(selector.call("lib/state_machines/branch.rb")).to contain_exactly(
        "test/unit/branch/branch_test.rb",
        "test/unit/branch/conflict_test.rb"
      )
    end

    it "returns nil when spec_pattern excludes all candidates" do
      create_file("spec/foo_spec.rb")
      selector = build(spec_pattern: "spec/requests/**/*_spec.rb")

      expect(selector.call("lib/foo.rb")).to be_nil
    end

    it "spec_files beats spec_mappings" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(
        spec_files: ["spec/explicit_spec.rb"],
        spec_mappings: { "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"] }
      )

      expect(selector.call("app/controllers/games_controller.rb")).to eq(["spec/explicit_spec.rb"])
    end

    it "spec_mappings beats spec_pattern when mapping exists" do
      create_file("spec/requests/games_overlay_spec.rb")
      create_file("spec/foo_spec.rb")
      selector = build(
        spec_mappings: { "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"] },
        spec_pattern: "spec/requests/**/*_spec.rb"
      )

      expect(selector.call("app/controllers/games_controller.rb")).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "normalizes leading ./ in source path when looking up mappings" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: {
                         "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"]
                       })

      expect(selector.call("./app/controllers/games_controller.rb")).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "normalizes absolute source path (under pwd) when looking up mappings" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: {
                         "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"]
                       })

      absolute = "#{Dir.pwd}/app/controllers/games_controller.rb"
      expect(selector.call(absolute)).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "coerces a non-string source path to a string before mapping lookup" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: {
                         "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"]
                       })

      pathname = Pathname.new("app/controllers/games_controller.rb")
      expect(selector.call(pathname)).to eq(["spec/requests/games_overlay_spec.rb"])
    end

    it "does not match a nil source against an empty-string mapping key" do
      create_file("spec/requests/games_overlay_spec.rb")
      selector = build(spec_mappings: { "" => ["spec/requests/games_overlay_spec.rb"] })

      expect(selector.call(nil)).to be_nil
    end
  end

  # Regression for EV-wqxu / GH #1278: isolators chdir workers into a per-
  # mutation sandbox to contain path-relativizing mutations. SpecSelector
  # must still resolve project-relative mappings when the sandbox CWD does
  # not contain the spec — falling back to Evilution::PROJECT_ROOT only when
  # the isolated-worker flag is set, so unrelated callers that intentionally
  # chdir (e.g. tests with fixture project layouts) keep their CWD-only
  # semantics.
  describe "isolated worker fallback" do
    let(:probe_relative_path) { "spec/evilution/spec_selector_spec.rb" }

    around do |example|
      original = Evilution.instance_variable_get(:@in_isolated_worker)
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, original)
    end

    it "falls back to PROJECT_ROOT for a project-relative mapping when flagged as isolated" do
      skip "PROJECT_ROOT spec missing" unless File.exist?(File.join(Evilution::PROJECT_ROOT, probe_relative_path))

      Evilution.in_isolated_worker!
      selector = build(spec_mappings: { "lib/foo.rb" => [probe_relative_path] })

      expect(selector.call("lib/foo.rb")).to eq([probe_relative_path])
    end

    it "does not fall back to PROJECT_ROOT when not flagged (preserves CWD-only contract)" do
      selector = build(spec_mappings: { "lib/foo.rb" => [probe_relative_path] })

      expect(selector.call("lib/foo.rb")).to be_nil
    end
  end
end
