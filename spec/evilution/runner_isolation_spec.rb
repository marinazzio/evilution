# frozen_string_literal: true

require "evilution/runner"
require "evilution/rails_detector"
require "fileutils"
require "tmpdir"

RSpec.describe Evilution::Runner, "isolation resolution" do
  around do |example|
    Dir.mktmpdir("evilution-runner-isolation") do |tmp|
      @tmp = tmp
      Evilution::RailsDetector.reset_cache!
      example.run
    end
  end

  def build_config(**overrides)
    Evilution::Config.new(
      target_files: [File.join(@tmp, "lib", "thing.rb")],
      format: :json,
      timeout: 5,
      quiet: true,
      baseline: false,
      isolation: :auto,
      skip_config_file: true,
      **overrides
    )
  end

  def write_plain_target
    FileUtils.mkdir_p(File.join(@tmp, "lib"))
    File.write(File.join(@tmp, "lib", "thing.rb"), "class Thing; end\n")
  end

  def write_rails_target
    FileUtils.mkdir_p(File.join(@tmp, "config"))
    FileUtils.mkdir_p(File.join(@tmp, "app", "models"))
    File.write(File.join(@tmp, "config", "application.rb"), "# Rails\n")
    File.write(File.join(@tmp, "app", "models", "user.rb"), "class User; end\n")
  end

  def resolved_isolator_class(runner)
    runner.send(:build_isolator).class
  end

  describe "with isolation: :auto" do
    it "selects Fork when any target lives under a Rails root" do
      write_rails_target
      config = build_config(target_files: [File.join(@tmp, "app", "models", "user.rb")])
      runner = described_class.new(config: config)
      expect(resolved_isolator_class(runner)).to eq(Evilution::Isolation::Fork)
    end

    it "selects InProcess when no target lives under a Rails root" do
      write_plain_target
      config = build_config
      runner = described_class.new(config: config)
      expect(resolved_isolator_class(runner)).to eq(Evilution::Isolation::InProcess)
    end
  end

  describe "with isolation: :fork" do
    it "always uses Fork regardless of Rails detection" do
      write_rails_target
      config = build_config(
        isolation: :fork,
        target_files: [File.join(@tmp, "app", "models", "user.rb")]
      )
      runner = described_class.new(config: config)
      expect(resolved_isolator_class(runner)).to eq(Evilution::Isolation::Fork)
    end
  end

  describe "with isolation: :in_process" do
    it "uses InProcess on a non-Rails project without warning" do
      write_plain_target
      config = build_config(isolation: :in_process)
      runner = described_class.new(config: config)
      expect { resolved_isolator_class(runner) }.not_to output.to_stderr
      expect(resolved_isolator_class(runner)).to eq(Evilution::Isolation::InProcess)
    end

    it "still uses InProcess on a Rails project but warns once to stderr" do
      write_rails_target
      config = build_config(
        isolation: :in_process,
        target_files: [File.join(@tmp, "app", "models", "user.rb")],
        quiet: false
      )
      expect { described_class.new(config: config) }.to output(/handle_interrupt|--isolation fork/).to_stderr
    end

    it "resolves to InProcess on a Rails project when explicitly requested" do
      write_rails_target
      config = build_config(
        isolation: :in_process,
        target_files: [File.join(@tmp, "app", "models", "user.rb")]
      )
      runner = described_class.new(config: config)
      expect(resolved_isolator_class(runner)).to eq(Evilution::Isolation::InProcess)
    end

    it "suppresses the warning when quiet is set" do
      write_rails_target
      config = build_config(
        isolation: :in_process,
        target_files: [File.join(@tmp, "app", "models", "user.rb")],
        quiet: true
      )
      runner = described_class.new(config: config)
      expect { runner.send(:build_isolator) }.not_to output.to_stderr
    end

    it "does not warn twice for repeated calls in the same run" do
      write_rails_target
      config = build_config(
        isolation: :in_process,
        target_files: [File.join(@tmp, "app", "models", "user.rb")],
        quiet: false
      )
      captured = StringIO.new
      orig = $stderr
      $stderr = captured
      runner = described_class.new(config: config) # first warn during initialize
      runner.send(:build_isolator) # should not warn again
      runner.send(:build_isolator)
      $stderr = orig
      expect(captured.string.scan("handle_interrupt").length).to eq(1)
    end
  end
end
