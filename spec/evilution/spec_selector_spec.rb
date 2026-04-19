# frozen_string_literal: true

require "tmpdir"
require "fileutils"
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
  end
end
