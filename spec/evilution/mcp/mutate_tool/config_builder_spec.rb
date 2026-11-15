# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::ConfigBuilder do
  describe ".build" do
    it "returns an Evilution::Config with MCP defaults" do
      config = described_class.build(files: ["lib/a.rb"], line_ranges: {}, params: {})

      expect(config).to be_a(Evilution::Config)
      expect(config.target_files).to eq(["lib/a.rb"])
      expect(config.format).to eq(:json)
      expect(config.quiet).to be(true)
      expect(config.preload).to be(false)
    end

    it "passes skip_config_file when skip_config is truthy" do
      # skip_config_file is consumed by Config#initialize; when true it skips loading the
      # config file. Verify behaviorally: a config file that sets a non-MCP key (timeout)
      # must NOT take effect when skip_config is true — Config keeps the default 30.
      allow(Evilution::Config::FileLoader).to receive(:load).and_return({ timeout: 99 })
      config = described_class.build(files: [], line_ranges: {}, params: { skip_config: true })

      expect(config.timeout).to eq(30)
      expect(config.format).to eq(:json)
      expect(config.quiet).to be(true)
    end

    it "does NOT skip the config file when skip_config is absent" do
      # Guards the `if params[:skip_config]` guard: without skip_config the config file
      # IS loaded, so its timeout value flows into the resulting Config.
      allow(Evilution::Config::FileLoader).to receive(:load).and_return({ timeout: 99 })
      config = described_class.build(files: [], line_ranges: {}, params: {})

      expect(config.timeout).to eq(99)
    end

    it "takes the files and lines changed since the ref given as since" do
      line_set = Evilution::LineSet.new([4..4])
      allow(Evilution::Git::SinceScope).to receive(:apply).and_return(
        Evilution::Git::SinceScope::Paths.new(files: ["lib/b.rb"], ranges: { "lib/b.rb" => line_set })
      )

      config = described_class.build(files: [], line_ranges: {}, params: { since: "main", skip_config: true })

      expect(Evilution::Git::SinceScope).to have_received(:apply).with("main", files: [], line_ranges: {})
      expect(config.target_files).to eq(["lib/b.rb"])
      expect(config.line_ranges).to eq("lib/b.rb" => line_set)
      expect(config.since).to eq("main")
    end

    it "hands git the ref stripped of the space around it" do
      allow(Evilution::Git::SinceScope).to receive(:apply)
        .and_return(Evilution::Git::SinceScope::Paths.new(files: [], ranges: {}))

      config = described_class.build(files: [], line_ranges: {}, params: { since: " main ", skip_config: true })

      expect(Evilution::Git::SinceScope).to have_received(:apply).with("main", files: [], line_ranges: {})
      expect(config.since).to eq("main")
    end

    it "rejects an empty since before git is asked about it" do
      allow(Evilution::Git::SinceScope).to receive(:apply)

      expect { described_class.build(files: [], line_ranges: {}, params: { since: "", skip_config: true }) }
        .to raise_error(Evilution::ConfigError, "--since needs a git ref, such as main or origin/main")
      expect(Evilution::Git::SinceScope).not_to have_received(:apply)
    end

    it "rejects since with a source glob target before git is asked about it" do
      allow(Evilution::Git::SinceScope).to receive(:apply)
      params = { since: "main", target: "source:lib/**/*.rb", skip_config: true }

      expect { described_class.build(files: [], line_ranges: {}, params: params) }
        .to raise_error(Evilution::ConfigError, /--target source:GLOB/)
      expect(Evilution::Git::SinceScope).not_to have_received(:apply)
    end

    it "leaves files and line ranges as given without since" do
      config = described_class.build(files: ["lib/a.rb"], line_ranges: { "lib/a.rb" => 1..2 }, params: { skip_config: true })

      expect(config.line_ranges).to eq("lib/a.rb" => 1..2)
      expect(config.since).to be_nil
    end

    it "copies spec overrides to spec_files" do
      config = described_class.build(files: [], line_ranges: {}, params: { spec: ["spec/a_spec.rb"] })
      expect(config.spec_files).to eq(["spec/a_spec.rb"])
    end

    it "leaves spec_files at the default when spec is absent" do
      # Guards the `if params[:spec]` guard: with no :spec key, opts[:spec_files] must
      # not be assigned, so Config keeps its empty-array default.
      config = described_class.build(files: [], line_ranges: {}, params: { skip_config: true })
      expect(config.spec_files).to eq([])
    end

    it "passes through documented keys" do
      params = { target: "Foo#bar", timeout: 5, jobs: 2, fail_fast: 1, suggest_tests: true,
                 incremental: true, integration: :minitest, isolation: :fork, baseline: false,
                 save_session: true }
      config = described_class.build(files: [], line_ranges: {}, params: params)

      expect(config.target).to eq("Foo#bar")
      expect(config.timeout).to eq(5)
      expect(config.jobs).to eq(2)
      expect(config.integration).to eq(:minitest)
    end

    it "skips nil passthrough values" do
      config = described_class.build(files: [], line_ranges: {}, params: { timeout: nil, skip_config: true })
      expect(config.timeout).not_to be_nil
    end

    describe "preload override" do
      it "defaults preload to false when not provided" do
        config = described_class.build(files: [], line_ranges: {}, params: {})
        expect(config.preload).to be(false)
      end

      it "passes through preload: <path> when provided" do
        config = described_class.build(files: [], line_ranges: {}, params: { preload: "spec/rails_helper.rb" })
        expect(config.preload).to eq("spec/rails_helper.rb")
      end

      it "passes through preload: false explicitly" do
        config = described_class.build(files: [], line_ranges: {}, params: { preload: false })
        expect(config.preload).to be(false)
      end

      it "keeps default when preload is nil" do
        config = described_class.build(files: [], line_ranges: {}, params: { preload: nil })
        expect(config.preload).to be(false)
      end

      it "raises ConfigError when preload: true is passed (schema disallows; validator catches)" do
        # MCP schema advertises preload as `string | false` (no `true`). If a client
        # bypasses the schema and sends `true`, Config's preload validator raises
        # so the user gets a clear error instead of silent misbehavior.
        expect do
          described_class.build(files: [], line_ranges: {}, params: { preload: true })
        end.to raise_error(Evilution::ConfigError, /preload must be nil, false, or a String path/)
      end
    end
  end
end
