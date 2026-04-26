# frozen_string_literal: true

require "tmpdir"
require "evilution/runner"

RSpec.describe "Evilution::Runner#configure_child_output" do
  before { Evilution::ChildOutput.log_dir = nil }
  after  { Evilution::ChildOutput.log_dir = nil }

  def runner_with(config)
    Evilution::Runner.new(config: config).tap { |r| r.send(:configure_child_output) }
  end

  def cfg(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  it "leaves ChildOutput.log_dir nil when quiet_children is false" do
    runner_with(cfg(quiet_children: false))
    expect(Evilution::ChildOutput.log_dir).to be_nil
  end

  it "creates the log dir and sets ChildOutput.log_dir when quiet_children is true" do
    Dir.mktmpdir do |parent|
      dir = File.join(parent, "ch")
      runner_with(cfg(quiet_children: true, quiet_children_dir: dir))
      expect(Evilution::ChildOutput.log_dir).to eq(dir)
      expect(File.directory?(dir)).to be(true)
    end
  end

  it "truncates the log dir on each run so prior-run files do not leak in" do
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "999.err")
      File.write(stale, "from previous run")
      runner_with(cfg(quiet_children: true, quiet_children_dir: dir))
      expect(File.exist?(stale)).to be(false)
    end
  end

  it "raises ConfigError pointing at --quiet-children-dir when the dir is not writable" do
    expect do
      runner_with(cfg(quiet_children: true, quiet_children_dir: "/nonexistent_root/cannot_write/here"))
    end.to raise_error(Evilution::ConfigError, /quiet_children_dir.*not writable.*--quiet-children-dir/)
  end
end
