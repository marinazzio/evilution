# frozen_string_literal: true

require_relative "../work_queue"

# Forward-declaration stub: the real Worker class lands in Task 9 (#843).
# Worker::Loop loads first and needs the namespace to exist. The unless-defined
# guard makes this stub inert when the real class is loaded.
class Evilution::Parallel::WorkQueue::Worker; end unless defined?(Evilution::Parallel::WorkQueue::Worker) && Evilution::Parallel::WorkQueue::Worker.is_a?(Class) # rubocop:disable Lint/EmptyClass,Layout/LineLength
