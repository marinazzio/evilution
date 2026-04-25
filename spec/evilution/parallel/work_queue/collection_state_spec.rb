# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/collection_state"

RSpec.describe Evilution::Parallel::WorkQueue do
  describe "::CollectionState (private constant)" do
    let(:klass) { described_class.send(:const_get, :CollectionState) }

    it "creates results array of given size" do
      state = klass.new(5)
      expect(state.results).to eq([nil, nil, nil, nil, nil])
    end

    it "starts with zero in_flight, zero next_index, nil first_error" do
      state = klass.new(5)
      expect(state.in_flight).to eq(0)
      expect(state.next_index).to eq(0)
      expect(state.first_error).to be_nil
    end

    it "exposes mutable accessors" do
      state = klass.new(2)
      state.results[0] = "a"
      state.in_flight = 1
      state.next_index = 1
      state.first_error = StandardError.new("boom")
      expect(state.results).to eq(["a", nil])
      expect(state.in_flight).to eq(1)
      expect(state.next_index).to eq(1)
      expect(state.first_error).to be_a(StandardError)
    end
  end
end
