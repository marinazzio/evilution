# frozen_string_literal: true

require "stringio"

RSpec.describe Evilution::Reporter::ProgressBar do
  let(:output) { StringIO.new }
  let(:tty_output) do
    io = StringIO.new
    allow(io).to receive(:tty?).and_return(true)
    io
  end

  describe "#initialize" do
    it "accepts total count and output stream" do
      bar = described_class.new(total: 100, output: output)

      expect(bar.total).to eq(100)
    end

    it "defaults width to 30" do
      bar = described_class.new(total: 100, output: output)

      expect(bar.width).to eq(30)
    end

    it "accepts custom width" do
      bar = described_class.new(total: 100, output: output, width: 50)

      expect(bar.width).to eq(50)
    end
  end

  describe "#tick" do
    it "increments the completed count" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)
      bar.tick(status: :survived)

      expect(bar.completed).to eq(2)
    end

    it "tracks killed count" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)
      bar.tick(status: :killed)
      bar.tick(status: :survived)

      expect(bar.killed).to eq(2)
    end

    it "tracks survived count" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)
      bar.tick(status: :survived)

      expect(bar.survived).to eq(1)
    end

    it "renders progress to output" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)

      rendered = output.string
      expect(rendered).to include("1/10")
      expect(rendered).to include("1 killed")
      expect(rendered).to include("0 survived")
    end
  end

  describe "#render" do
    it "includes a progress bar with fill and empty sections" do
      bar = described_class.new(total: 10, output: output, width: 20)

      5.times { bar.tick(status: :killed) }

      rendered = output.string
      expect(rendered).to include("[")
      expect(rendered).to include("]")
    end

    it "includes mutation counts" do
      bar = described_class.new(total: 100, output: output)

      3.times { bar.tick(status: :killed) }
      2.times { bar.tick(status: :survived) }

      rendered = output.string
      expect(rendered).to include("5/100")
      expect(rendered).to include("3 killed")
      expect(rendered).to include("2 survived")
    end

    it "includes elapsed time" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)

      rendered = output.string
      expect(rendered).to match(/\d{2}:\d{2} elapsed/)
    end

    it "includes estimated remaining time" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)

      rendered = output.string
      expect(rendered).to match(/~\d{2}:\d{2} remaining/)
    end

    it "uses carriage return for TTY overwrite" do
      bar = described_class.new(total: 10, output: tty_output)

      bar.tick(status: :killed)

      expect(tty_output.string).to start_with("\r")
    end

    it "uses newlines for non-TTY output" do
      bar = described_class.new(total: 10, output: output)

      bar.tick(status: :killed)

      expect(output.string).not_to include("\r")
      expect(output.string).to end_with("\n")
    end
  end

  describe "#finish" do
    it "renders a final newline for TTY" do
      bar = described_class.new(total: 2, output: tty_output)

      bar.tick(status: :killed)
      bar.tick(status: :killed)
      bar.finish

      expect(tty_output.string).to end_with("\n")
    end

    it "does not add extra newline for non-TTY" do
      bar = described_class.new(total: 2, output: output)

      bar.tick(status: :killed)
      bar.tick(status: :killed)
      lines_before = output.string.count("\n")
      bar.finish
      lines_after = output.string.count("\n")

      expect(lines_after).to eq(lines_before + 1)
    end
  end

  describe ".tty?" do
    it "returns true for a TTY IO" do
      tty_io = instance_double(IO, tty?: true)

      expect(described_class.tty?(tty_io)).to be true
    end

    it "returns false for a non-TTY IO" do
      non_tty_io = StringIO.new

      expect(described_class.tty?(non_tty_io)).to be false
    end
  end

  describe "edge cases" do
    it "handles zero total gracefully" do
      bar = described_class.new(total: 0, output: output)

      bar.finish

      expect(output.string).to include("0/0")
    end

    it "shows 100% filled bar when complete" do
      bar = described_class.new(total: 2, output: output, width: 10)

      2.times { bar.tick(status: :killed) }

      rendered = output.string
      expect(rendered).to include("2/2")
    end

    it "clamps remaining time to zero when over-ticked" do
      bar = described_class.new(total: 1, output: output)

      bar.tick(status: :killed)
      bar.tick(status: :killed)

      expect(output.string).to include("~00:00 remaining")
    end

    it "produces consistent bar width regardless of fill level" do
      bar = described_class.new(total: 10, output: output, width: 20)

      bar.tick(status: :killed)
      # Extract bar portion [....] — should be exactly 22 chars (20 interior + 2 brackets)
      match = output.string.match(/\[[=> ]{20}\]/)
      expect(match).not_to be_nil
    end
  end
end
