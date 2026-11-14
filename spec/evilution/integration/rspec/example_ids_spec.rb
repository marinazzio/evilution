# frozen_string_literal: true

require "tmpdir"
require "evilution/integration/rspec"

RSpec.describe Evilution::Integration::RSpec::ExampleIds do
  def example_at(path, scoped_id, status: :failed, run_time: 0.0)
    double("Example", metadata: { rerun_file_path: path, scoped_id: scoped_id },
                      execution_result: double("ExecutionResult", status: status, run_time: run_time))
  end

  describe ".of" do
    it "names an example by its absolute spec file and its position in it" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a_spec.rb"), "")
        real = File.realpath(File.join(dir, "a_spec.rb"))

        expect(described_class.of(example_at(real, "1:2"))).to eq("#{real}[1:2]")
      end
    end

    it "gives the same name whether the file was given relative or absolute" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a_spec.rb"), "")
        absolute = described_class.of(example_at(File.join(dir, "a_spec.rb"), "1:1"))
        relative = Dir.chdir(dir) { described_class.of(example_at("./a_spec.rb", "1:1")) }

        expect(relative).to eq(absolute)
      end
    end

    it "resolves a symlinked path to the file it points at" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a_spec.rb"), "")
        File.symlink(dir, "#{dir}_link")

        expect(described_class.of(example_at(File.join("#{dir}_link", "a_spec.rb"), "1:1")))
          .to eq(described_class.of(example_at(File.join(dir, "a_spec.rb"), "1:1")))
      ensure
        File.delete("#{dir}_link") if File.symlink?("#{dir}_link")
      end
    end

    it "still names an example whose file is not there" do
      expect(described_class.of(example_at("/nowhere/a_spec.rb", "1:1"))).to eq("/nowhere/a_spec.rb[1:1]")
    end
  end

  describe ".failed" do
    it "returns the ids of the failed examples only" do
      world = double("World", all_examples: [
                       example_at("/p/a_spec.rb", "1:1", status: :passed),
                       example_at("/p/a_spec.rb", "1:2"),
                       example_at("/p/a_spec.rb", "1:3", status: :pending),
                       example_at("/p/b_spec.rb", "1:1")
                     ])

      expect(described_class.failed(world)).to eq(["/p/a_spec.rb[1:2]", "/p/b_spec.rb[1:1]"])
    end

    it "returns nothing for a world that cannot list its examples" do
      expect(described_class.failed(Object.new)).to eq([])
    end
  end

  describe ".durations" do
    it "returns how long each example that ran took, by its id" do
      world = double("World", all_examples: [
                       example_at("/p/a_spec.rb", "1:1", status: :passed, run_time: 0.5),
                       example_at("/p/a_spec.rb", "1:2", status: :failed, run_time: 0.25)
                     ])

      expect(described_class.durations(world)).to eq("/p/a_spec.rb[1:1]" => 0.5, "/p/a_spec.rb[1:2]" => 0.25)
    end

    it "leaves out the examples that did not run" do
      world = double("World", all_examples: [
                       example_at("/p/a_spec.rb", "1:1", status: :pending, run_time: 0.0),
                       example_at("/p/a_spec.rb", "1:2", status: nil, run_time: nil)
                     ])

      expect(described_class.durations(world)).to eq({})
    end

    it "returns nothing for a world that cannot list its examples" do
      expect(described_class.durations(Object.new)).to eq({})
    end
  end

  describe ".executed_count" do
    it "counts the examples that ran, pending ones included" do
      world = double("World", all_examples: [
                       example_at("/p/a_spec.rb", "1:1", status: :passed),
                       example_at("/p/a_spec.rb", "1:2", status: :failed),
                       example_at("/p/a_spec.rb", "1:3", status: :pending),
                       example_at("/p/a_spec.rb", "1:4", status: nil)
                     ])

      expect(described_class.executed_count(world)).to eq(3)
    end

    it "is nil for a world that cannot list its examples" do
      expect(described_class.executed_count(Object.new)).to be_nil
    end
  end
end
