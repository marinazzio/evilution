# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/isolation/fork"
require "evilution/integration/rspec"
require "evilution/temp_dir_tracker"

RSpec.describe "Temp-file mutation integration" do
  let(:project_dir) { Dir.mktmpdir("evilution_integ") }
  let(:lib_dir) { File.join(project_dir, "lib") }
  let(:spec_dir) { File.join(project_dir, "spec") }
  let(:dummy_spec) { File.join(spec_dir, "dummy_spec.rb") }

  let(:original_source) { "class Greeter\n  def greet\n    'hello'\n  end\nend\n" }
  let(:mutated_source) { "class Greeter\n  def greet\n    nil\n  end\nend\n" }
  let(:source_path) { File.join(lib_dir, "greeter.rb") }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_path,
      original_source: original_source,
      mutated_source: mutated_source
    )
  end

  before do
    FileUtils.mkdir_p(lib_dir)
    FileUtils.mkdir_p(spec_dir)
    File.write(source_path, original_source)
    File.write(dummy_spec, "RSpec.describe('noop') { it('passes') { expect(true).to be true } }\n")
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "original file protection" do
    it "never modifies the original source file during a forked mutation run" do
      $LOAD_PATH.unshift(lib_dir)
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      # Write child's observation of the file to a marker for parent to read
      marker = File.join(project_dir, "file_during_run.txt")
      test_command = lambda { |m|
        integration.call(m)
        File.write(marker, File.read(m.file_path))
        { passed: false }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      expect(File.read(source_path)).to eq(original_source)
      expect(File.read(marker)).to eq(original_source)
    ensure
      $LOAD_PATH.delete(lib_dir)
    end

    it "never modifies non-LOAD_PATH files during a forked mutation run" do
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      marker = File.join(project_dir, "file_during_run.txt")
      test_command = lambda { |m|
        integration.call(m)
        File.write(marker, File.read(m.file_path))
        { passed: false }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      expect(File.read(source_path)).to eq(original_source)
      expect(File.read(marker)).to eq(original_source)
    end
  end

  describe "temp directory cleanup" do
    it "cleans up sandbox directory on normal completion" do
      $LOAD_PATH.unshift(lib_dir)
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      # Record the sandbox dir from the child
      marker = File.join(project_dir, "sandbox.txt")
      test_command = lambda { |m|
        File.write(marker, ENV.fetch("TMPDIR", ""))
        integration.call(m)
        { passed: false }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      sandbox = File.read(marker)
      expect(sandbox).not_to be_empty
      expect(Dir.exist?(sandbox)).to be false
    ensure
      $LOAD_PATH.delete(lib_dir)
    end

    it "cleans up sandbox directory when test command raises" do
      $LOAD_PATH.unshift(lib_dir)
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      marker = File.join(project_dir, "sandbox.txt")
      test_command = lambda { |m|
        File.write(marker, ENV.fetch("TMPDIR", ""))
        integration.call(m)
        raise "simulated crash"
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      sandbox = File.read(marker)
      expect(Dir.exist?(sandbox)).to be false
    ensure
      $LOAD_PATH.delete(lib_dir)
    end

    it "parent TempDirTracker cleans up registered dirs via defense-in-depth" do
      dir = Dir.mktmpdir("evilution")
      Evilution::TempDirTracker.register(dir)
      isolator = Evilution::Isolation::Fork.new

      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.5)

      expect(Dir.exist?(dir)).to be false
      expect(Evilution::TempDirTracker.tracked_dirs).to be_empty
    end
  end

  describe "LOAD_PATH isolation" do
    it "does not leak temp dirs into parent $LOAD_PATH after fork" do
      $LOAD_PATH.unshift(lib_dir)
      load_path_before = $LOAD_PATH.dup
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      test_command = lambda { |m|
        integration.call(m)
        { passed: false }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      expect($LOAD_PATH).to eq(load_path_before)
    ensure
      $LOAD_PATH.delete(lib_dir)
    end

    it "does not leak temp entries into parent $LOADED_FEATURES after fork" do
      $LOAD_PATH.unshift(lib_dir)
      features_before = $LOADED_FEATURES.dup
      integration = Evilution::Integration::RSpec.new(test_files: [dummy_spec])
      isolator = Evilution::Isolation::Fork.new

      test_command = lambda { |m|
        integration.call(m)
        { passed: false }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 10)

      new_features = $LOADED_FEATURES - features_before
      temp_features = new_features.select { |f| f.include?("evilution") && f.start_with?(Dir.tmpdir) }
      expect(temp_features).to be_empty
    ensure
      $LOAD_PATH.delete(lib_dir)
    end
  end
end
