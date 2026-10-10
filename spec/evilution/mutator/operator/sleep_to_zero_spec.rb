# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SleepToZero do
  def mutations_of(body)
    Tempfile.create(["sleep_to_zero", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(delay, n)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The body of the method after each mutation.
  def mutated_bodies(body)
    mutations_of(body).map { |m| m.mutated_source.lines[2..-3].join }
  end

  describe "#call" do
    it "replaces a duration held in a variable with 0" do
      expect(mutated_bodies("    sleep delay\n")).to eq(["    sleep 0\n"])
      expect(mutated_bodies("    sleep(delay)\n")).to eq(["    sleep(0)\n"])
    end

    it "replaces a computed duration as a whole" do
      expect(mutated_bodies("    sleep delay * 2**n\n")).to eq(["    sleep 0\n"])
      expect(mutated_bodies("    sleep(@config.retry_interval)\n")).to eq(["    sleep(0)\n"])
      expect(mutated_bodies("    sleep [delay, 30].min\n")).to eq(["    sleep 0\n"])
    end

    it "replaces the duration of Kernel.sleep" do
      expect(mutated_bodies("    Kernel.sleep(delay)\n")).to eq(["    Kernel.sleep(0)\n"])
      expect(mutated_bodies("    ::Kernel.sleep delay\n")).to eq(["    ::Kernel.sleep 0\n"])
    end

    it "keeps the rest of the statement" do
      expect(mutated_bodies("    sleep delay if n.positive?\n")).to eq(["    sleep 0 if n.positive?\n"])
      expect(mutated_bodies("    n.times { sleep(delay) }\n")).to eq(["    n.times { sleep(0) }\n"])
    end

    # IntegerLiteral, FloatLiteral and RationalLiteral already take these to zero.
    it "leaves a literal duration to the literal operators" do
      expect(mutations_of("    sleep 5\n    sleep(0.5)\n    sleep 1r\n    sleep 0\n")).to be_empty
    end

    it "leaves a sleep without a duration, or with more than one argument, alone" do
      expect(mutations_of("    sleep\n    sleep(delay, n)\n    sleep(*delay)\n")).to be_empty
    end

    it "leaves a sleep sent to another receiver alone" do
      expect(mutations_of("    delay.sleep(n)\n    Async::Task.sleep(delay)\n")).to be_empty
    end

    it "leaves other calls alone" do
      expect(mutations_of("    wait(delay)\n    Timeout.timeout(delay) { n }\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_of("    n\n    sleep delay\n").map(&:line)).to eq([4])
    end

    it "produces valid Ruby" do
      bodies = ["    sleep delay\n", "    sleep(delay * 2)\n", "    Kernel.sleep delay if n\n", "    n.times { sleep(delay) }\n",
                "    sleep delay ? 1 : n\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations.length).to eq(5)
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    sleep delay\n").map(&:operator_name)).to eq(["sleep_to_zero"])
    end
  end
end
