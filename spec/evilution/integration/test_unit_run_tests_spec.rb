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
  end
end
