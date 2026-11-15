# frozen_string_literal: true

require "tmpdir"

RSpec.describe Evilution::Cache::RunFingerprint do
  around do |example|
    Dir.mktmpdir("evilution_fingerprint") { |dir| Dir.chdir(dir) { example.run } }
  end

  def config(**options)
    Evilution::Config.new(skip_config_file: true, **options)
  end

  def fingerprint(**options)
    described_class.new(config(**options)).to_s
  end

  it "is the same for the same settings" do
    expect(fingerprint(timeout: 5)).to eq(fingerprint(timeout: 5))
  end

  it "ignores settings that cannot change a verdict" do
    expect(fingerprint(jobs: 1, format: :text)).to eq(fingerprint(jobs: 4, format: :json))
  end

  {
    integration: %i[rspec minitest],
    isolation: %i[fork in_process],
    profile: %i[default strict],
    timeout: [5, 6],
    baseline: [true, false],
    example_targeting: [true, false],
    related_specs_heuristic: [false, true],
    fallback_to_full_suite: [false, true],
    stop_on_kill: [true, false],
    example_targeting_fallback: %i[full_file unresolved],
    example_targeting_strategy: %i[lexical coverage],
    warmup: %i[none rails],
    timeout_floor: [10, 5],
    timeout_ceiling: [60, 90]
  }.each do |key, (one, other)|
    it "changes with #{key}" do
      expect(fingerprint(key => one)).not_to eq(fingerprint(key => other))
    end
  end

  it "changes with whether mutations no test executes are skipped" do
    expect(fingerprint(example_targeting_strategy: :coverage))
      .not_to eq(fingerprint(example_targeting_strategy: :coverage, skip_uncovered: false))
  end

  it "changes with the adaptive timeout's settings" do
    expect(fingerprint(timeout_factor: 10)).not_to eq(fingerprint(timeout_factor: 5))
  end

  it "changes with whether the timeout adapts to the baseline" do
    expect(fingerprint).not_to eq(fingerprint(timeout: Evilution::Config::DEFAULTS[:timeout]))
  end

  it "is a SHA-256 hex digest" do
    expect(fingerprint).to match(/\A\h{64}\z/)
  end

  it "is worked out once" do
    fp = described_class.new(config)
    before = fp.to_s
    File.write("Gemfile.lock", "changed")

    expect(fp.to_s).to eq(before)
  end

  it "changes with the Ruby version" do
    before = fingerprint
    stub_const("RUBY_VERSION", "0.0.1")

    expect(fingerprint).not_to eq(before)
  end

  it "changes with the Ruby engine" do
    before = fingerprint
    stub_const("RUBY_ENGINE", "other")

    expect(fingerprint).not_to eq(before)
  end

  %w[.rspec spec/spec_helper.rb spec/rails_helper.rb spec/support/a.rb test/test_helper.rb test/support/a.rb
     Gemfile.lock gems.locked].each do |helper|
    it "changes when #{helper} changes" do
      FileUtils.mkdir_p(File.dirname(helper))
      File.write(helper, "1")
      before = fingerprint
      File.write(helper, "2")

      expect(fingerprint).not_to eq(before)
    end
  end

  it "keeps the helpers when a preload file is given" do
    File.write("boot.rb", "1")
    File.write("Gemfile.lock", "a")
    before = fingerprint(preload: "boot.rb")
    File.write("Gemfile.lock", "b")

    expect(fingerprint(preload: "boot.rb")).not_to eq(before)
  end

  it "changes with the evilution version" do
    before = fingerprint
    stub_const("Evilution::VERSION", "0.0.0-test")

    expect(fingerprint).not_to eq(before)
  end

  it "changes when a spec helper changes" do
    FileUtils.mkdir_p("spec/support")
    File.write("spec/spec_helper.rb", "1")
    before = fingerprint
    File.write("spec/support/matchers.rb", "2")

    expect(fingerprint).not_to eq(before)
  end

  it "changes when the lockfile changes" do
    File.write("Gemfile.lock", "a")
    before = fingerprint
    File.write("Gemfile.lock", "b")

    expect(fingerprint).not_to eq(before)
  end

  it "changes when the preload file changes" do
    File.write("boot.rb", "1")
    before = fingerprint(preload: "boot.rb")
    File.write("boot.rb", "2")

    expect(fingerprint(preload: "boot.rb")).not_to eq(before)
  end
end
