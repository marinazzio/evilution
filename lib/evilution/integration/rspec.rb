# frozen_string_literal: true

require "stringio"
require_relative "base"

module Evilution
  module Integration
    class RSpec < Base
      def initialize(test_files: nil)
        @test_files = test_files
        super()
      end

      def call(mutation)
        apply_mutation(mutation)
        run_rspec
      ensure
        restore_original(mutation)
      end

      private

      attr_reader :test_files

      def apply_mutation(mutation)
        @original_content = File.read(mutation.file_path)
        File.write(mutation.file_path, mutation.mutated_source)
      end

      def restore_original(mutation)
        File.write(mutation.file_path, @original_content) if @original_content
      end

      def run_rspec
        out = StringIO.new
        err = StringIO.new
        args = build_args

        status = ::RSpec::Core::Runner.run(args, out, err)

        { passed: status.zero? }
      rescue StandardError => e
        { passed: false, error: e.message }
      end

      def build_args
        files = test_files || detect_test_files
        ["--format", "progress", "--no-color", "--order", "defined", *files]
      end

      def detect_test_files
        return ["spec"] if Dir.exist?("spec")

        []
      end
    end
  end
end
