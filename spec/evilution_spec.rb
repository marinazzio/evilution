# frozen_string_literal: true

RSpec.describe Evilution do
  it "has a version number" do
    expect(Evilution::VERSION).not_to be nil
  end

  it "defines the Error class" do
    expect(Evilution::Error).to be < StandardError
  end

  describe ".project_base_dir" do
    around do |example|
      previous = Evilution.instance_variable_get(:@in_isolated_worker)
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, previous)
    end

    it "returns Dir.pwd when the isolated-worker flag is unset" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(Evilution.project_base_dir).to eq(dir)
        end
      end
    end

    it "returns Evilution::PROJECT_ROOT when the isolated-worker flag is set" do
      Evilution.in_isolated_worker!

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(Evilution.project_base_dir).to eq(Evilution::PROJECT_ROOT)
        end
      end
    end
  end

  describe ".single_mutation_process?" do
    around do |example|
      previous = Evilution.instance_variable_get(:@single_mutation_process)
      Evilution.instance_variable_set(:@single_mutation_process, nil)
      example.run
    ensure
      Evilution.instance_variable_set(:@single_mutation_process, previous)
    end

    it "is false until the process is declared one" do
      expect(Evilution.single_mutation_process?).to be(false)
    end

    it "is true once it is" do
      Evilution.single_mutation_process!

      expect(Evilution.single_mutation_process?).to be(true)
    end
  end

  describe ".while_running_tests" do
    around do |example|
      previous = Evilution.instance_variable_get(:@running_tests)
      previous_error = Evilution.instance_variable_get(:@tests_left_by)
      example.run
    ensure
      Evilution.instance_variable_set(:@running_tests, previous)
      Evilution.instance_variable_set(:@tests_left_by, previous_error)
    end

    it "reports no test run outside the block" do
      expect(Evilution.running_tests?).to be(false)
    end

    it "reports a test run inside the block" do
      inside = Evilution.while_running_tests { Evilution.running_tests? }

      expect(inside).to be(true)
    end

    it "returns the value of the block" do
      expect(Evilution.while_running_tests { :verdict }).to eq(:verdict)
    end

    it "reports no test run once the block has returned" do
      Evilution.while_running_tests { nil }

      expect(Evilution.running_tests?).to be(false)
    end

    it "knows the exception that left the block" do
      error = RuntimeError.new("boom")

      expect { Evilution.while_running_tests { raise error } }.to raise_error(error)

      expect(Evilution.died_running_tests?(error)).to be(true)
    end

    it "does not take another exception for the one that left the block" do
      expect { Evilution.while_running_tests { raise "boom" } }.to raise_error("boom")

      expect(Evilution.died_running_tests?(RuntimeError.new("boom"))).to be(false)
    end

    it "forgets the exception once a later block has returned" do
      error = RuntimeError.new("boom")
      expect { Evilution.while_running_tests { raise error } }.to raise_error(error)

      Evilution.while_running_tests { nil }

      expect(Evilution.died_running_tests?(error)).to be(false)
    end

    it "takes any exception for the tests' while the block is still open" do
      inside = Evilution.while_running_tests { Evilution.died_running_tests?(RuntimeError.new("other")) }

      expect(inside).to be(true)
    end

    it "reports no test run once the block has raised" do
      expect { Evilution.while_running_tests { raise "boom" } }.to raise_error("boom")

      expect(Evilution.running_tests?).to be(false)
    end
  end
end
