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

    expect(add_examples).to include(a_string_matching(/calculator_examples\.rb\[[\d:]+\]\z/))
    expect(sub_examples).to include(a_string_matching(/calculator_examples\.rb\[[\d:]+\]\z/))
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

  # The cached map is keyed on them: a change to any of them can change which
  # lines run.
  it "records the project files the build loaded, and none from outside the project" do
    ledger = File.join(fixture_dir, "ledger.rb")
    ledger_spec = File.join(fixture_dir, "ledger_examples.rb")
    map = described_class.new(spec_files: [ledger_spec], target_files: [target], project_root: fixture_dir).call

    expect(map.loaded_files).to include(ledger, ledger_spec)
    expect(map.loaded_files).to all(start_with("#{fixture_dir}/"))
    expect(map.loaded_files).to eq(map.loaded_files.uniq)
  end

  # Loaded before the build counted any line, as the code under test often is.
  it "records a project file required before the build, too" do
    root = File.expand_path("../../..", __dir__)
    map = described_class.new(spec_files: [spec], target_files: [target], project_root: root).call

    expect(map.loaded_files).to include(File.join(root, "lib/evilution/coverage/map_builder.rb"))
  end

  # A gem installed inside the project (vendor/bundle) changes with the lockfile.
  it "leaves out the files of installed gems inside the project" do
    allow(Gem).to receive(:path).and_return([fixture_dir])
    map = described_class.new(spec_files: [spec], target_files: [target],
                              project_root: File.dirname(fixture_dir)).call

    expect(map.loaded_files).not_to include(start_with("#{fixture_dir}/"))
  end

  # An example from a shared group is defined in the shared file, but it runs
  # only as part of the spec file that includes the group; on its own the
  # shared file defines no example and may not even load.
  describe "examples from a shared group" do
    including = File.join(fixture_dir, "shared_group_examples.rb")
    shared = File.join(fixture_dir, "shared", "adds_group.rb")
    add_line = File.readlines(target).index { |l| l.include?("a + b") } + 1

    it "credits the line to the spec file that includes the group" do
      map = described_class.new(spec_files: [including], target_files: [target]).call
      examples = map.examples_for(target, add_line)

      expect(examples).not_to be_empty
      expect(examples).to all(start_with("#{including}["))
      expect(examples).not_to include(start_with(shared))
    end

    it "records a location that runs exactly the covering example" do
      map = described_class.new(spec_files: [including], target_files: [target]).call
      location = map.examples_for(target, add_line).first
      script = <<~RUBY
        require "rspec/core"
        exit RSpec::Core::Runner.run([#{location.inspect}, "--format", "progress"])
      RUBY
      # Run away from this project's .rspec, which requires its own spec helper.
      out, err, status = Open3.capture3(RbConfig.ruby, "-e", script, chdir: fixture_dir)

      expect(status).to be_success, err
      expect(out).to include("1 example, 0 failures")
    end
  end

  # Under fork isolation nothing loads RSpec into the parent before the build
  # (the canary runs it in a child), and without --preload neither does the
  # project: the build's child loads it itself.
  it "builds the map in a process that has not loaded RSpec" do
    script = <<~RUBY
      require "evilution"
      require "evilution/coverage/map_builder"
      abort "RSpec already loaded" if defined?(::RSpec)
      map = Evilution::Coverage::MapBuilder.new(spec_files: [#{spec.inspect}], target_files: [#{target.inspect}]).call
      line = File.readlines(#{target.inspect}).index { |l| l.include?("a + b") } + 1
      puts map.built?(#{target.inspect})
      puts map.examples_for(#{target.inspect}, line).size
    RUBY
    lib_dir = File.expand_path("../../../lib", __dir__)
    # Run away from this project's .rspec, which requires its own spec helper.
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib_dir, "-e", script, chdir: fixture_dir)

    expect(status).to be_success, err
    expect(out.lines.map(&:strip)).to eq(%w[true 1])
    expect(err).to be_empty
  end

  # A build that cannot finish leaves targeting to the lexical filter; the
  # reason must reach the one-line warning, not a backtrace on stderr.
  describe "a build that fails in its child" do
    it "raises Evilution::Error with the child's error, printing nothing" do
      allow(Evilution::Coverage::Recorder).to receive(:new).and_raise(NameError, "uninitialized constant Boom")
      builder = described_class.new(spec_files: [spec], target_files: [target])

      expect { expect { builder.call }.to raise_error(Evilution::Error, "NameError: uninitialized constant Boom") }
        .not_to output.to_stderr_from_any_process
    end

    it "raises Evilution::Error naming the exit when the child sends nothing" do
      allow(Evilution::Coverage::Recorder).to receive(:new) { exit!(3) }
      builder = described_class.new(spec_files: [spec], target_files: [target])

      expect { builder.call }.to raise_error(Evilution::Error, /coverage map builder exited without a map \(.*exit 3\)/)
    end
  end

  describe ".absolute_location" do
    it "expands a ./-relative example id against the root, keeping the id" do
      expect(described_class.absolute_location("./spec/a_spec.rb[1:2:1]", "/proj"))
        .to eq("/proj/spec/a_spec.rb[1:2:1]")
    end

    it "keeps an already-absolute example id" do
      expect(described_class.absolute_location("/x/spec/a_spec.rb[1:2]", "/proj"))
        .to eq("/x/spec/a_spec.rb[1:2]")
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

    # A forked process counts its lines in its own copy of the counters, which
    # the build never reads, while a mutation applied before the fork reaches it.
    it "vouches for no line when an example forks" do
      forking = File.join(fixture_dir, "forking_examples.rb")
      map = described_class.new(spec_files: [forking], target_files: [ledger]).call

      expect(map.uncovered?(ledger, [line_of.call("@total -= amount")])).to be(false)
      expect(map.uncovered?(ledger, [line_of.call("@total += amount")])).to be(false)
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
