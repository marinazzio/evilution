# frozen_string_literal: true

require_relative "../work_queue"

# CollectionState is a top-level private constant on WorkQueue (not under a
# sub-namespace) so Dispatcher accesses it via const_get.
class Evilution::Parallel::WorkQueue
  CollectionState = Struct.new(:results, :in_flight, :next_index, :first_error) do
    def initialize(item_count)
      super(Array.new(item_count), 0, 0, nil)
    end
  end
  private_constant :CollectionState
end
