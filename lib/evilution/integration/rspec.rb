# frozen_string_literal: true

require "stringio"
require_relative "base"

module Evilution
  module Integration
    class RSpec < Base
      def initialize(test_files: nil)
        @test_files = test_files
        @rspec_loaded = false
        super()
      end

      def call(mutation)
        ensure_rspec_loaded
        apply_mutation(mutation)
        run_rspec(mutation)
      ensure
        restore_original(mutation)
      end

      private

      attr_reader :test_files

      def ensure_rspec_loaded
        return if @rspec_loaded

        require "rspec/core"
        @rspec_loaded = true
      rescue LoadError => e
        raise Evilution::Error, "rspec-core is required but not available: #{e.message}"
      end

      def apply_mutation(mutation)
        @original_content = File.read(mutation.file_path)
        File.write(mutation.file_path, mutation.mutated_source)
      end

      def restore_original(mutation)
        File.write(mutation.file_path, @original_content) if @original_content
      end

      def run_rspec(mutation)
        # Reset RSpec world between runs so each mutation gets a clean slate
        ::RSpec.reset

        out = StringIO.new
        err = StringIO.new
        args = build_args(mutation)

        status = ::RSpec::Core::Runner.run(args, out, err)

        { passed: status.zero? }
      rescue StandardError => e
        { passed: false, error: e.message }
      end

      def build_args(mutation)
        files = test_files || detect_test_files(mutation)
        ["--format", "progress", "--no-color", "--order", "defined", *files]
      end

      def detect_test_files(mutation)
        # Convention: lib/foo/bar.rb -> spec/foo/bar_spec.rb
        candidates = spec_file_candidates(mutation.file_path)
        found = candidates.select { |f| File.exist?(f) }
        return found unless found.empty?

        # Fallback: find spec/ directory relative to the mutation's project root
        fallback = fallback_spec_dir(mutation.file_path)
        return [fallback] if fallback

        []
      end

      def fallback_spec_dir(source_path)
        # Derive spec/ from mutation's project, not CWD
        if source_path.include?("/lib/")
          project_root = source_path.split(%r{/lib/}, 2).first
          spec_dir = File.join(project_root, "spec")
          return spec_dir if Dir.exist?(spec_dir)
        end

        # For relative paths, fall back to CWD's spec/
        return "spec" if Dir.exist?("spec")

        nil
      end

      def spec_file_candidates(source_path)
        candidates = []

        if source_path.start_with?("lib/")
          # lib/foo/bar.rb -> spec/foo/bar_spec.rb
          relative = source_path.sub(%r{^lib/}, "")
          spec_name = relative.sub(/\.rb$/, "_spec.rb")
          candidates << File.join("spec", spec_name)
          candidates << File.join("spec", "unit", spec_name)
        elsif source_path.include?("/lib/")
          # /absolute/path/lib/foo/bar.rb -> /absolute/path/spec/foo/bar_spec.rb
          prefix, relative = source_path.split(%r{/lib/}, 2)
          spec_name = relative.sub(/\.rb$/, "_spec.rb")
          candidates << File.join(prefix, "spec", spec_name)
          candidates << File.join(prefix, "spec", "unit", spec_name)
        end

        # Same directory: foo/bar.rb -> foo/bar_spec.rb
        sibling_spec = source_path.sub(/\.rb$/, "_spec.rb")
        candidates << sibling_spec

        # Subdirectory spec/ variant: foo/bar.rb -> foo/spec/bar_spec.rb
        dir = File.dirname(source_path)
        base = File.basename(source_path, ".rb")
        candidates << File.join(dir, "spec", "#{base}_spec.rb")

        candidates.uniq
      end
    end
  end
end
