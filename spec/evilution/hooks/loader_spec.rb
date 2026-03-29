# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Hooks::Loader do
  describe ".call" do
    it "loads a hook file that returns a proc and registers it" do
      hook_file = Tempfile.new(["hook", ".rb"])
      hook_file.write("proc { |payload| payload[:called] = true }")
      hook_file.flush

      registry = Evilution::Hooks::Registry.new
      described_class.call(registry, worker_process_start: hook_file.path)

      expect(registry.handlers_for(:worker_process_start).length).to eq(1)
    ensure
      hook_file&.close
      hook_file&.unlink
    end

    it "supports multiple events" do
      pre_file = Tempfile.new(["pre_hook", ".rb"])
      pre_file.write("proc { |_| nil }")
      pre_file.flush

      post_file = Tempfile.new(["post_hook", ".rb"])
      post_file.write("proc { |_| nil }")
      post_file.flush

      registry = Evilution::Hooks::Registry.new
      described_class.call(registry,
                           mutation_insert_pre: pre_file.path,
                           mutation_insert_post: post_file.path)

      expect(registry.handlers_for(:mutation_insert_pre).length).to eq(1)
      expect(registry.handlers_for(:mutation_insert_post).length).to eq(1)
    ensure
      pre_file&.close
      pre_file&.unlink
      post_file&.close
      post_file&.unlink
    end

    it "supports an array of file paths for one event" do
      file1 = Tempfile.new(["hook1", ".rb"])
      file1.write("proc { |_| nil }")
      file1.flush

      file2 = Tempfile.new(["hook2", ".rb"])
      file2.write("proc { |_| nil }")
      file2.flush

      registry = Evilution::Hooks::Registry.new
      described_class.call(registry, worker_process_start: [file1.path, file2.path])

      expect(registry.handlers_for(:worker_process_start).length).to eq(2)
    ensure
      file1&.close
      file1&.unlink
      file2&.close
      file2&.unlink
    end

    it "executes the loaded proc when the hook fires" do
      hook_file = Tempfile.new(["hook", ".rb"])
      hook_file.write('proc { |payload| File.write(payload[:marker_path], "fired") }')
      hook_file.flush

      marker = Tempfile.new("marker")
      registry = Evilution::Hooks::Registry.new
      described_class.call(registry, worker_process_start: hook_file.path)

      registry.fire(:worker_process_start, marker_path: marker.path)

      expect(File.read(marker.path)).to eq("fired")
    ensure
      hook_file&.close
      hook_file&.unlink
      marker&.close
      marker&.unlink
    end

    it "raises ConfigError when hook file does not exist" do
      registry = Evilution::Hooks::Registry.new

      expect { described_class.call(registry, worker_process_start: "/nonexistent/hook.rb") }
        .to raise_error(Evilution::ConfigError, /hook file not found/i)
    end

    it "raises ConfigError when hook file does not return a Proc" do
      hook_file = Tempfile.new(["bad_hook", ".rb"])
      hook_file.write('"not a proc"')
      hook_file.flush

      registry = Evilution::Hooks::Registry.new

      expect { described_class.call(registry, worker_process_start: hook_file.path) }
        .to raise_error(Evilution::ConfigError, /must return a Proc/i)
    ensure
      hook_file&.close
      hook_file&.unlink
    end

    it "raises ArgumentError for unknown events" do
      hook_file = Tempfile.new(["hook", ".rb"])
      hook_file.write("proc { |_| nil }")
      hook_file.flush

      registry = Evilution::Hooks::Registry.new

      expect { described_class.call(registry, bogus_event: hook_file.path) }
        .to raise_error(ArgumentError, /unknown hook event/i)
    ensure
      hook_file&.close
      hook_file&.unlink
    end

    it "returns the registry" do
      registry = Evilution::Hooks::Registry.new
      result = described_class.call(registry)

      expect(result).to eq(registry)
    end

    it "handles nil config gracefully" do
      registry = Evilution::Hooks::Registry.new
      result = described_class.call(registry, nil)

      expect(result).to eq(registry)
    end

    it "handles string event keys from YAML" do
      hook_file = Tempfile.new(["hook", ".rb"])
      hook_file.write("proc { |_| nil }")
      hook_file.flush

      registry = Evilution::Hooks::Registry.new
      described_class.call(registry, "worker_process_start" => hook_file.path)

      expect(registry.handlers_for(:worker_process_start).length).to eq(1)
    ensure
      hook_file&.close
      hook_file&.unlink
    end
  end
end
