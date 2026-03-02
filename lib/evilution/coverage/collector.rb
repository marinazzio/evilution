# frozen_string_literal: true

require "coverage"

module Evilution
  module Coverage
    class Collector
      def call(test_files:)
        read_io, write_io = IO.pipe

        pid = ::Process.fork do
          read_io.close
          result = collect_coverage(test_files)
          Marshal.dump(result, write_io)
          write_io.close
          exit!(0)
        end

        write_io.close
        data = read_io.read
        read_io.close
        ::Process.wait(pid)

        Marshal.load(data) # rubocop:disable Security/MarshalLoad
      ensure
        read_io&.close
        write_io&.close
      end

      private

      def collect_coverage(test_files)
        ::Coverage.start
        test_files.each { |f| load(f) }
        ::Coverage.result
      end
    end
  end
end
