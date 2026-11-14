# frozen_string_literal: true

require "spec_helper"
require "open3"
require "evilution/coverage/map_builder"

RSpec.describe Evilution::Coverage::MapBuilder do
  fixture_dir = File.expand_path("../../support/fixtures/coverage", __dir__)
  target = File.join(fixture_dir, "calculator.rb")
  # Named *_examples.rb (not *_spec.rb) so the host suite's default
  # spec/**/*_spec.rb pattern never auto-loads it: were calculator.rb required
  # in the parent before the build fork, the child's require would be a no-op
  # and ::Coverage would never instrument it.
  spec = File.join(fixture_dir, "calculator_examples.rb")

  # The builder runs a real RSpec process-in-process; guard wall time.
  it "maps each method's line to the example that exercises it" do
    map = described_class.new(spec_files: [spec], target_files: [target]).call

    add_line = File.readlines(target).index { |l| l.include?("a + b") } + 1
    sub_line = File.readlines(target).index { |l| l.include?("a - b") } + 1

    add_examples = map.examples_for(target, add_line)
    sub_examples = map.examples_for(target, sub_line)

    expect(add_examples).to include(a_string_matching(/calculator_examples\.rb:\d+/))
    expect(sub_examples).to include(a_string_matching(/calculator_examples\.rb:\d+/))
    # The "adds" example must not be credited with the subtraction line.
    expect(add_examples).not_to eq(sub_examples)
    expect(map.built?(target)).to be(true)
  end

  it "records ABSOLUTE example locations so they replay regardless of CWD" do
    map = described_class.new(spec_files: [spec], target_files: [target]).call
    add_line = File.readlines(target).index { |l| l.include?("a + b") } + 1

    map.examples_for(target, add_line).each do |loc|
      expect(loc).to start_with("/") # absolute path, not RSpec's "./spec/..." form
    end
  end

  describe ".absolute_location" do
    it "expands a ./-relative location against the root, keeping the line suffix" do
      expect(described_class.absolute_location("./spec/a_spec.rb:5", "/proj"))
        .to eq("/proj/spec/a_spec.rb:5")
    end

    it "keeps a nested line suffix and an already-absolute path" do
      expect(described_class.absolute_location("/x/spec/a_spec.rb:5:9", "/proj"))
        .to eq("/x/spec/a_spec.rb:5:9")
    end
  end

  describe "lines no example executes" do
    ledger = File.join(fixture_dir, "ledger.rb")
    ledger_spec = File.join(fixture_dir, "ledger_examples.rb")
    line_of = ->(text) { File.readlines(ledger).index { |l| l.include?(text) } + 1 }
    refund_body = line_of.call("@total -= amount")
    limit = line_of.call("LIMIT = 100")

    it "marks a method body no example calls as uncovered, and nothing that ran while the file loaded" do
      map = described_class.new(spec_files: [ledger_spec], target_files: [ledger]).call

      expect(map.uncovered?(ledger, [line_of.call("@total -= amount")])).to be(true)
      expect(map.uncovered?(ledger, [line_of.call("@total += amount")])).to be(false)
      expect(map.uncovered?(ledger, [line_of.call("LIMIT = 100")])).to be(false)
      expect(map.uncovered?(ledger, [line_of.call("attr_reader")])).to be(false)
      expect(map.uncovered?(ledger, [line_of.call("def refund")])).to be(false)
      expect(map.built_from?([ledger_spec])).to be(true)
    end

    it "vouches for no line when a spec file fails to load" do
      broken = File.join(fixture_dir, "broken_examples.rb")
      map = described_class.new(spec_files: [ledger_spec, broken], target_files: [ledger]).call

      expect(map.uncovered?(ledger, [line_of.call("@total -= amount")])).to be(false)
    end

    it "vouches for no line when the run stops before every example ran" do
      fail_fast = File.join(fixture_dir, "fail_fast_examples.rb")
      map = described_class.new(spec_files: [fail_fast], target_files: [ledger]).call

      expect(map.uncovered?(ledger, [line_of.call("@total -= amount")])).to be(false)
    end

    # A preload runs in the parent before the build forks. Counting from before
    # it keeps what ran while the files loaded; a file loaded while counting
    # was off shows those lines at zero and cannot be trusted.
    define_method(:build_in_subprocess) do |load_while:|
      script = <<~RUBY
        require "coverage"
        require "rspec/core"
        require "evilution"
        require "evilution/coverage/map_builder"
        Coverage.setup(lines: true)
        Coverage.resume
        require #{ledger.inspect} if #{load_while == :counting}
        Coverage.suspend
        require #{ledger.inspect}
        map = Evilution::Coverage::MapBuilder.new(spec_files: [#{ledger_spec.inspect}], target_files: [#{ledger.inspect}]).call
        puts map.uncovered?(#{ledger.inspect}, [#{refund_body}])
        puts map.uncovered?(#{ledger.inspect}, [#{limit}])
      RUBY
      lib_dir = File.expand_path("../../../lib", __dir__)
      # Run away from this project's .rspec, which requires its own spec helper.
      out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib_dir, "-e", script, chdir: fixture_dir)
      raise "build failed: #{err}" unless status.success?

      out.lines.map(&:strip)
    end

    it "keeps the lines a file ran while it loaded before the build, when counting was on" do
      expect(build_in_subprocess(load_while: :counting)).to eq(%w[true false])
    end

    it "vouches for no line of a file loaded before the build while counting was off" do
      expect(build_in_subprocess(load_while: :suspended)).to eq(%w[false false])
    end
  end
end
