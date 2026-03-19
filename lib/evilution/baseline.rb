# frozen_string_literal: true

require_relative "spec_resolver"

module Evilution
  class Baseline
    Result = Struct.new(:failed_spec_files, :duration) do
      def initialize(**)
        super
        freeze
      end

      def failed?
        !failed_spec_files.empty?
      end
    end

    def initialize(spec_resolver: SpecResolver.new, timeout: 30)
      @spec_resolver = spec_resolver
      @timeout = timeout
    end

    def call(subjects)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      spec_files = resolve_unique_spec_files(subjects)
      failed = Set.new

      spec_files.each do |spec_file|
        failed.add(spec_file) unless run_spec_file(spec_file)
      end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      Result.new(failed_spec_files: failed, duration: duration)
    end

    def run_spec_file(spec_file)
      read_io, write_io = IO.pipe
      pid = fork_spec_runner(spec_file, read_io, write_io)
      write_io.close
      read_result(read_io, pid)
    rescue StandardError
      false
    ensure
      read_io&.close
      write_io&.close
    end

    def fork_spec_runner(spec_file, read_io, write_io)
      Process.fork do
        read_io.close
        $stdout.reopen(File::NULL, "w")
        $stderr.reopen(File::NULL, "w")

        require "rspec/core"
        ::RSpec.reset
        status = ::RSpec::Core::Runner.run(
          ["--format", "progress", "--no-color", "--order", "defined", spec_file]
        )
        Marshal.dump({ passed: status.zero? }, write_io)
        write_io.close
        exit!(status.zero? ? 0 : 1)
      end
    end

    GRACE_PERIOD = 0.5

    def read_result(read_io, pid)
      if read_io.wait_readable(@timeout)
        data = read_io.read
        Process.wait(pid)
        return false if data.empty?

        result = Marshal.load(data) # rubocop:disable Security/MarshalLoad
        result[:passed]
      else
        terminate_child(pid)
        false
      end
    end

    def terminate_child(pid)
      Process.kill("TERM", pid) rescue nil # rubocop:disable Style/RescueModifier
      _, status = Process.waitpid2(pid, Process::WNOHANG)
      return if status

      sleep(GRACE_PERIOD)
      _, status = Process.waitpid2(pid, Process::WNOHANG)
      return if status

      Process.kill("KILL", pid) rescue nil # rubocop:disable Style/RescueModifier
      Process.wait(pid) rescue nil # rubocop:disable Style/RescueModifier
    end

    private

    def resolve_unique_spec_files(subjects)
      subjects.map { |s| @spec_resolver.call(s.file_path) || "spec" }.uniq
    end
  end
end
