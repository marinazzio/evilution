# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "evilution/integration/test_unit"

RSpec.describe Evilution::Integration::TestUnit, "baseline runner" do
  let(:tmpdir) { Dir.mktmpdir("test_unit_baseline_spec") }

  after { FileUtils.rm_rf(tmpdir) }

  def write_test_file(filename, body)
    path = File.join(tmpdir, filename)
    File.write(path, body)
    path
  end

  describe ".baseline_runner" do
    it "returns a callable lambda" do
      runner = described_class.baseline_runner

      expect(runner).to respond_to(:call)
    end

    it "delegates to .run_baseline_test_file with the given path" do
      allow(described_class).to receive(:run_baseline_test_file)

      described_class.baseline_runner.call("test/foo_test.rb")

      expect(described_class).to have_received(:run_baseline_test_file).with("test/foo_test.rb")
    end
  end

  describe ".run_baseline_test_file" do
    it "reports a pass when all loaded tests pass" do
      path = write_test_file("passing_test.rb", <<~RUBY)
        require "test-unit"

        class TestUnitBaselinePassing < Test::Unit::TestCase
          def test_passes
            assert_equal 1, 1
          end
        end
      RUBY

      result = described_class.run_baseline_test_file(path)

      expect(result).to eq(Evilution::Baseline::Report.build(passed: true))
    end

    it "reports a failure when at least one loaded test fails" do
      path = write_test_file("failing_test.rb", <<~RUBY)
        require "test-unit"

        class TestUnitBaselineFailing < Test::Unit::TestCase
          def test_fails
            assert_equal 1, 2
          end
        end
      RUBY

      result = described_class.run_baseline_test_file(path)

      expect(result[:passed]).to be false
    end

    it "names each failing test with its first message line" do
      path = write_test_file("detail_test.rb", <<~RUBY)
        require "test-unit"

        class TestUnitBaselineDetail < Test::Unit::TestCase
          def test_passes = assert_equal(1, 1)
          def test_fails = assert_equal(1, 2, "numbers differ")
          def test_raises = raise(ArgumentError, "bad input")
          def test_pending = pend("later")
        end
      RUBY

      result = described_class.run_baseline_test_file(path)

      expect(result[:failure_count]).to eq(2)
      expect(result[:failures].map { |failure| failure[:id] })
        .to contain_exactly("test_fails(TestUnitBaselineDetail)", "test_raises(TestUnitBaselineDetail)")
      expect(result[:failures].map { |failure| failure[:message] })
        .to contain_exactly(a_string_starting_with("numbers differ"), "ArgumentError: bad input")
    end

    it "names every failing test the way a mutation run does" do
      path = write_test_file("ids_test.rb", <<~RUBY)
        require "test-unit"

        class TestUnitBaselineIds < Test::Unit::TestCase
          def test_passes = assert_equal(1, 1)
          def test_fails = assert_equal(1, 2)
          def test_raises = raise(ArgumentError, "bad input")
          def test_pending = pend("later")
        end
      RUBY

      expect(described_class.run_baseline_test_file(path)[:failed_ids])
        .to contain_exactly("test_fails(TestUnitBaselineIds)", "test_raises(TestUnitBaselineIds)")
    end

    it "loads every *_test.rb under a directory when given a directory" do
      Dir.mkdir(File.join(tmpdir, "nested"))
      write_test_file("nested/a_test.rb", <<~RUBY)
        require "test-unit"
        class TestUnitBaselineDirA < Test::Unit::TestCase
          def test_a_passes; assert_true true; end
        end
      RUBY
      write_test_file("nested/b_test.rb", <<~RUBY)
        require "test-unit"
        class TestUnitBaselineDirB < Test::Unit::TestCase
          def test_b_passes; assert_true true; end
        end
      RUBY

      result = described_class.run_baseline_test_file(File.join(tmpdir, "nested"))

      expect(result[:passed]).to be true
    end

    it "does not print test output to the parent process stdout" do
      path = write_test_file("quiet_test.rb", <<~RUBY)
        require "test-unit"
        class TestUnitBaselineQuiet < Test::Unit::TestCase
          def test_quiet; assert_true true; end
        end
      RUBY

      expect { described_class.run_baseline_test_file(path) }.not_to output.to_stdout
    end

    it "stubs Test::Unit::AutoRunner so its at_exit handler does not fire on evilution exit" do
      path = write_test_file("autorun_test.rb", <<~RUBY)
        require "test-unit"
        class TestUnitBaselineAutorun < Test::Unit::TestCase
          def test_autorun; assert_true true; end
        end
      RUBY

      described_class.run_baseline_test_file(path)

      require "test-unit"
      expect(Test::Unit::AutoRunner.need_auto_run?).to be false
    end
  end

  describe ".baseline_test_files" do
    it "returns the original path as a single-element array when given a file" do
      path = write_test_file("foo_test.rb", "")

      expect(described_class.baseline_test_files(path)).to eq([path])
    end

    it "globs **/*_test.rb when given a directory" do
      Dir.mkdir(File.join(tmpdir, "sub"))
      a_path = write_test_file("a_test.rb", "")
      sub_path = write_test_file("sub/b_test.rb", "")
      write_test_file("helper.rb", "")
      write_test_file("README.md", "")

      result = described_class.baseline_test_files(tmpdir)

      expect(result).to contain_exactly(a_path, sub_path)
    end
  end
end
