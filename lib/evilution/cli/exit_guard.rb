# frozen_string_literal: true

require_relative "../cli"
require_relative "../isolation/in_process"

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
# One such ending has a status of its own. A mutation that takes the process
# down under in-process isolation leaves a run that measured nothing, and Ruby
# would end it with 1: the status of a score below the minimum. It ends with
# the status of a tool error instead. The hook that reports the death is the
# first to run, so the status is left to this one, after the project's hooks
# and evilution's own cleanup.
#
# The hook belongs to the process that installed it. Evilution forks workers,
# and a fork inherits its parent's at_exit hooks; a worker running this one
# would exit with the parent's status and skip its own ending. The guard
# therefore remembers its process and stands down anywhere else.
class Evilution::CLI::ExitGuard
  DIED = 2

  attr_accessor :status

  def initialize(register: nil, exiter: nil, pid_source: nil, streams: nil, died: nil)
    @register = register || ->(&hook) { at_exit(&hook) }
    @exiter = exiter || ->(code) { exit!(code) }
    @streams = streams || -> { [$stdout, $stderr, STDOUT, STDERR] } # rubocop:disable Style/GlobalStdStream -- the process's own, whatever the globals point at
    @pid_source = pid_source || -> { Process.pid }
    @died = died || -> { Evilution::Isolation::InProcess.died? }
    @status = nil
  end

  def install
    @pid = @pid_source.call
    @register.call { fire }
    self
  end

  private

  def fire
    return unless @pid_source.call == @pid

    status = final_status
    return if status.nil?

    flush_streams
    @exiter.call(status)
  end

  def final_status
    return @status unless @status.nil?

    DIED if @died.call
  end

  # `exit!` leaves buffered output where it stands, so anything written by the
  # report, or by a hook that ran before this one, has to be pushed out first.
  # The process's own streams are flushed as well as the current ones: a run
  # that died under in-process isolation is left with the null streams of the
  # mutation it was testing.
  def flush_streams
    @streams.call.each do |stream|
      stream.flush
    rescue IOError, Errno::EBADF
      nil
    end
  end
end
