# frozen_string_literal: true

# Gives evilution the final word on the process exit status.
#
# `--preload` loads the project's own spec helper into the parent process, and
# whatever that helper installs comes along with it. SimpleCov's at_exit hook
# calls `exit` with its own status when coverage is below the configured
# minimum, which replaces the status evilution computed and breaks a CI step
# reading it (EV-g8ya / GH #1608).
#
# at_exit hooks run last-registered-first, so a hook installed before the
# preload is the last one standing. It exits with `exit!`, which is immediate
# and cannot be overridden by anything left in the queue — by then every other
# hook, evilution's own temp-directory cleanup included, has already run.
#
# With no status recorded, evilution did not finish normally: an exception is on
# its way out, and Ruby's own handling decides the status instead.
#
# The hook belongs to the process that installed it. Evilution forks workers,
# and a fork inherits its parent's at_exit hooks; a worker running this one
# would exit with the parent's status and skip its own ending. The guard
# therefore remembers its process and stands down anywhere else.
class Evilution::CLI::ExitGuard
  attr_accessor :status

  def initialize(register: nil, exiter: nil, pid_source: nil, streams: nil)
    @register = register || ->(&hook) { at_exit(&hook) }
    @exiter = exiter || ->(code) { exit!(code) }
    @streams = streams || -> { [$stdout, $stderr] }
    @pid_source = pid_source || -> { Process.pid }
    @status = nil
  end

  def install
    @pid = @pid_source.call
    @register.call { fire }
    self
  end

  private

  def fire
    return if @status.nil?
    return unless @pid_source.call == @pid

    flush_streams
    @exiter.call(@status)
  end

  # `exit!` leaves buffered output where it stands, so anything written by the
  # report, or by a hook that ran before this one, has to be pushed out first.
  def flush_streams
    @streams.call.each do |stream|
      stream.flush
    rescue IOError, Errno::EBADF
      nil
    end
  end
end
