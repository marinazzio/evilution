# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Isolation::Fork do
  subject(:isolator) { described_class.new }

  let(:tmpfile) { Tempfile.new("fork_spec") }
  let(:original_content) { "original content" }
  let(:mutation) do
    double("Mutation", file_path: tmpfile.path, original_source: original_content)
  end

  before do
    File.write(tmpfile.path, original_content)
  end

  after do
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "returns killed when test command fails" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
      expect(result.mutation).to eq(mutation)
    end

    it "returns survived when test command passes" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_survived
    end

    it "returns timeout when child exceeds time limit" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "cleans up tracked temp dirs after a timeout" do
      dir = Dir.mktmpdir("evilution")
      Evilution::TempDirTracker.register(dir)

      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(Dir.exist?(dir)).to be false
      expect(Evilution::TempDirTracker.tracked_dirs).to be_empty
    end

    it "cleans up sandbox temp directory after child timeout" do
      dirs_before = Dir.glob(File.join(Dir.tmpdir, "evilution-run*"))

      test_command = lambda { |_m|
        Dir.mktmpdir("evilution")
        sleep 10
        { passed: true }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      dirs_after = Dir.glob(File.join(Dir.tmpdir, "evilution-run*"))
      new_dirs = dirs_after - dirs_before
      expect(new_dirs).to be_empty
    end

    it "sends SIGTERM before SIGKILL on timeout" do
      test_command = lambda { |_m|
        Signal.trap("TERM") { exit!(42) }
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "escalates to SIGKILL when child ignores SIGTERM" do
      test_command = lambda { |_m|
        Signal.trap("TERM", "IGNORE")
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "returns error when child writes empty result" do
      test_command = lambda { |_m|
        # Exit without writing a result, causing the OS to close the pipe
        exit!(0)
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
    end

    it "returns error when test command raises" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
    end

    it "records duration" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.duration).to be > 0
    end

    it "passes test_command from result to MutationResult" do
      test_command = ->(_m) { { passed: false, test_command: "rspec --format progress spec" } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.test_command).to eq("rspec --format progress spec")
    end

    it "sets test_command to nil when not in result" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.test_command).to be_nil
    end

    it "suppresses child stdout so it does not leak to parent" do
      test_command = lambda do |_m|
        $stdout.write("noisy stdout from child\n")
        { passed: false }
      end

      reader, writer = IO.pipe
      original_stdout = $stdout.dup
      $stdout.reopen(writer)

      begin
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
        $stdout.reopen(original_stdout)
        writer.close
        captured = reader.read
      ensure
        $stdout.reopen(original_stdout)
        reader.close unless reader.closed?
        writer.close unless writer.closed?
        original_stdout.close
      end

      expect(captured).not_to include("noisy")
    end

    it "suppresses child stderr so it does not leak to parent" do
      test_command = lambda do |_m|
        $stderr.write("noisy stderr from child\n")
        { passed: false }
      end

      reader, writer = IO.pipe
      original_stderr = $stderr.dup
      $stderr.reopen(writer)

      begin
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
        $stderr.reopen(original_stderr)
        writer.close
        captured = reader.read
      ensure
        $stderr.reopen(original_stderr)
        reader.close unless reader.closed?
        writer.close unless writer.closed?
        original_stderr.close
      end

      expect(captured).not_to include("noisy")
    end

    it "fires worker_process_start hook after fork" do
      hook_fired = false
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) { hook_fired = true }
      isolator = described_class.new(hooks: hooks)

      test_command = lambda do |_m|
        # hook_fired is set in the child process; verify via side effect
        { passed: hook_fired }
      end

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_survived
    end

    it "works without hooks (backwards compatible)" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
    end

    it "captures parent_rss_kb before forking" do
      skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.parent_rss_kb).to be_a(Integer)
      expect(result.parent_rss_kb).to be > 0
    end

    it "does not compute memory_delta_kb (cross-process comparison)" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.memory_delta_kb).to be_nil
    end

    it "isolates mutations from parent process" do
      parent_value = "original"
      test_command = lambda do |_m|
        parent_value = "mutated_in_child"
        { passed: false }
      end

      isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(parent_value).to eq("original")
    end
  end
end
