# frozen_string_literal: true

require_relative "../work_queue"

# Process-global registry of live worker process-group ids (pgids).
#
# EV-jwao / GH #1332: EV-cnx8 made each Worker its own process-group leader so a
# stuck worker's whole subtree can be group-killed. Side effect: a terminal
# Ctrl-C delivers SIGINT only to the parent's foreground group, so workers (now
# in their own groups) no longer receive it -- and the parent's fatal-signal
# death skips work_queue#map's `ensure cleanup_workers`, leaking any worker that
# was actively running a (possibly blocking) mutation at interrupt time.
#
# Runner#install_signal_handler reads this registry from inside the trap and
# forwards INT/TERM to each worker group before re-raising to DEFAULT.
#
# Signal-safety: under MRI a trap handler runs on the main thread between VM
# instructions, so it must not acquire a Mutex (the main thread may hold it ->
# deadlock). register/unregister therefore swap @pgids for a freshly built
# frozen array via a single atomic reference assignment (copy-on-write). The
# trap reads the current reference once and iterates that complete, immutable
# snapshot -- no torn reads, no lock.
module Evilution::Parallel::WorkQueue::WorkerRegistry
  @pgids = [].freeze

  class << self
    # Frozen snapshot. Safe to read from a signal handler.
    attr_reader :pgids

    def register(pgid)
      @pgids = (@pgids + [pgid]).freeze
    end

    def unregister(pgid)
      @pgids = @pgids.reject { |existing| existing == pgid }.freeze
    end

    def signal_all(sig)
      @pgids.each do |pgid|
        Process.kill(sig, -pgid)
      rescue Errno::ESRCH
        # Group already gone (worker + subtree reaped) -- nothing to signal.
        nil
      end
    end
  end
end
