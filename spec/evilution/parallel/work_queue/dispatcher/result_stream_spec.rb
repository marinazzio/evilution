# frozen_string_literal: true

require "evilution/parallel/work_queue"

RSpec.describe Evilution::Parallel::WorkQueue::Dispatcher::ResultStream do
  it "hands nothing on until flushed" do
    seen = []
    stream = described_class.new(->(index, value) { seen << [index, value] })
    stream.push(1, :a)

    expect(seen).to be_empty
  end

  it "hands every pushed item on once, in the order pushed" do
    seen = []
    stream = described_class.new(->(index, value) { seen << [index, value] })
    stream.push(1, :a)
    stream.push(0, :b)
    stream.flush
    stream.flush

    expect(seen).to eq([[1, :a], [0, :b]])
  end

  it "is stopped once the caller answers :stop, and stays so" do
    answers = [:stop, nil]
    stream = described_class.new(->(_index, _value) { answers.shift })
    stream.push(0, :a)
    stream.push(1, :b)
    stream.flush

    expect(stream).to be_stopped
  end

  it "is not stopped while the caller answers anything else" do
    stream = described_class.new(->(_index, _value) { :continue })
    expect(stream.stopped?).to be(false)

    stream.push(0, :a)
    stream.flush
    expect(stream.stopped?).to be(false)
  end

  it "takes no caller at all" do
    stream = described_class.new(nil)
    stream.push(0, :a)

    expect { stream.flush }.not_to raise_error
    expect(stream).not_to be_stopped
  end
end
