# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "evilution/integration/test_unit"
require "evilution/integration/test_unit_crash_detector"

# Exercises Evilution::Integration::TestUnit's per-mutation dispatch path.
# Each example loads a freshly-named TestCase subclass into the host process
# so the integration can resolve, dispatch, and classify it.
RSpec.describe Evilution::Integration::TestUnit, "#run_tests" do
  let(:tmpdir) { Dir.mktmpdir("test_unit_run_spec") }
  let(:mutation) { double("mutation", file_path: "lib/foo.rb") }

  after { FileUtils.rm_rf(tmpdir) }

  def write_test_file(filename, body)
    path = File.join(tmpdir, filename)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def build_integration(test_file:)
    described_class.new(test_files: [test_file])
  end

  describe "passed run" do
    it "returns passed: true when the resolved test file's tests all pass" do
      path = write_test_file("test/passes_test.rb", <<~RUBY)
        require "test-unit"
        class RunTestsPassing < Test::Unit::TestCase
          def test_ok; assert_equal 1, 1; end
        end
      RUBY

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:passed]).to be true
    end

    it "includes a test_command field describing the dispatched files" do
      path = write_test_file("test/passes2_test.rb", <<~RUBY)
        require "test-unit"
        class RunTestsPassing2 < Test::Unit::TestCase
          def test_ok; assert_equal 1, 1; end
        end
      RUBY

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:test_command]).to include(path)
    end
  end

  describe "failed run" do
    it "returns passed: false when at least one assertion fails" do
      path = write_test_file("test/fails_test.rb", <<~RUBY)
        require "test-unit"
        class RunTestsFailing < Test::Unit::TestCase
          def test_fails; assert_equal 1, 2; end
        end
      RUBY

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:passed]).to be false
      expect(result[:test_crashed]).to be_falsey
    end
  end

  describe "crash-only run" do
    it "marks the result as test_crashed: true and surfaces the exception class" do
      path = write_test_file("test/crashes_test.rb", <<~RUBY)
        require "test-unit"
        class RunTestsCrashing < Test::Unit::TestCase
          def test_raises; raise ArgumentError, "boom"; end
        end
      RUBY

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:passed]).to be false
      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to eq("ArgumentError")
      expect(result[:error]).to include("ArgumentError")
    end

    it "drops error_class when crashes span multiple exception classes" do
      path = write_test_file("test/mixed_crashes_test.rb", <<~RUBY)
        require "test-unit"
        class RunTestsMixedCrashes < Test::Unit::TestCase
          def test_arg; raise ArgumentError; end
          def test_type; raise TypeError; end
        end
      RUBY

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to be_nil
    end
  end

  describe "0 dispatched tests" do
    it "returns an Evilution::Error result when the test file registers no Test::Unit subclasses" do
      path = write_test_file("test/empty_test.rb", "# no test-unit classes here\n")

      result = build_integration(test_file: path).send(:run_tests, mutation)

      expect(result[:passed]).to be false
      expect(result[:error_class]).to eq("Evilution::Error")
      expect(result[:error]).to include("no Test::Unit tests executed")
    end
  end

  describe "unresolved spec" do
    it "returns unresolved: true when no test_files were provided and the resolver yields nothing" do
      integration = described_class.new(test_files: nil)
      allow_any_instance_of(Evilution::SpecSelector).to receive(:call).and_return(nil)

      result = integration.send(:run_tests, mutation)

      expect(result[:passed]).to be false
      expect(result[:unresolved]).to be true
      expect(result[:error]).to include("no matching test resolved for lib/foo.rb")
    end
  end

  describe "fallback_to_full_suite" do
    it "globs test/**/*_test.rb when no spec resolves and fallback is enabled" do
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p("test")
        File.write("test/sample_test.rb", <<~RUBY)
          require "test-unit"
          class RunTestsFallback < Test::Unit::TestCase
            def test_ok; assert_equal 1, 1; end
          end
        RUBY

        integration = described_class.new(test_files: nil, fallback_to_full_suite: true)
        allow_any_instance_of(Evilution::SpecSelector).to receive(:call).and_return(nil)

        result = integration.send(:run_tests, mutation)

        expect(result[:passed]).to be true
        expect(result[:test_command]).to include("test/sample_test.rb")
      end
    end

    # EV-ajby / GH #1376: when a source stays :unresolved (e.g. behaviour-named
    # layouts that never mirror the lib path), the warning must name both
    # recovery paths so the user can opt into a full-suite run.
    it "names --fallback-full-suite in the unresolved warning when fallback is disabled" do
      integration = described_class.new(test_files: nil, fallback_to_full_suite: false)
      allow_any_instance_of(Evilution::SpecSelector).to receive(:call).and_return(nil)

      expect { integration.send(:run_tests, mutation) }
        .to output(%r{No matching test found for lib/foo\.rb, marking mutation unresolved.*--fallback-full-suite}m)
        .to_stderr
    end
  end

  # Regression for EV-52hf / GH #1326 (shared TestLoadPath fix): a Test::Unit
  # test doing `require "test_helper"` (relying on -Itest) must load without
  # LoadError when run in-process.
  describe "loading a test that requires a bare test_helper (EV-52hf)" do
    around do |example|
      saved = $LOAD_PATH.dup
      example.run
    ensure
      $LOAD_PATH.replace(saved)
    end

    it "resolves require \"test_helper\" via the test root on $LOAD_PATH" do
      FileUtils.mkdir_p(File.join(tmpdir, "test", "unit"))
      helper = File.join(tmpdir, "test", "test_helper.rb")
      File.write(helper, "EV52HF_TU_HELPER = true\n")
      path = write_test_file("test/unit/tu_helper_test.rb", <<~RUBY)
        require "test_helper"
        require "test-unit"
        class RunTestsHelperReq < Test::Unit::TestCase
          def test_ok; assert_equal 1, 1; end
        end
      RUBY

      # Anchor the project base at the temp project so the helper's test/ root
      # is added to $LOAD_PATH (real projects keep test files inside the base).
      allow(Evilution).to receive(:project_base_dir).and_return(tmpdir)
      result = nil
      expect { result = build_integration(test_file: path).send(:run_tests, mutation) }.not_to raise_error
      expect(result[:error]).to be_nil
      expect(result[:passed]).to be true
      expect(defined?(EV52HF_TU_HELPER)).to eq("constant")
    ensure
      $LOADED_FEATURES.delete(helper)
      Object.send(:remove_const, :EV52HF_TU_HELPER) if defined?(EV52HF_TU_HELPER)
    end
  end
end
