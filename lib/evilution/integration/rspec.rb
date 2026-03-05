# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"
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
        @original_content = nil
        @temp_dir = nil
        @lock_file = nil
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
        subpath = resolve_require_subpath(mutation.file_path)

        if subpath
          @temp_dir = Dir.mktmpdir("evilution")
          dest = File.join(@temp_dir, subpath)
          FileUtils.mkdir_p(File.dirname(dest))
          File.write(dest, mutation.mutated_source)
          $LOAD_PATH.unshift(@temp_dir)
        else
          # Fallback: direct write when file isn't under any $LOAD_PATH entry.
          # Acquire an exclusive lock to prevent concurrent workers from corrupting the file.
          lock_path = File.join(Dir.tmpdir, "evilution-#{File.expand_path(mutation.file_path).hash.abs}.lock")
          @lock_file = File.open(lock_path, File::CREAT | File::RDWR) # rubocop:disable Style/FileOpen
          @lock_file.flock(File::LOCK_EX)
          @original_content = File.read(mutation.file_path)
          File.write(mutation.file_path, mutation.mutated_source)
        end
      end

      def restore_original(mutation)
        if @temp_dir
          $LOAD_PATH.delete(@temp_dir)
          $LOADED_FEATURES.reject! { |f| f.start_with?(@temp_dir) }
          FileUtils.rm_rf(@temp_dir)
          @temp_dir = nil
        elsif @original_content
          File.write(mutation.file_path, @original_content)
          @lock_file&.flock(File::LOCK_UN)
          @lock_file&.close
          @lock_file = nil
        end
      end

      def resolve_require_subpath(file_path)
        absolute = File.expand_path(file_path)

        $LOAD_PATH.each do |entry|
          dir = File.expand_path(entry)
          prefix = dir.end_with?("/") ? dir : "#{dir}/"
          next unless absolute.start_with?(prefix)

          return absolute.delete_prefix(prefix)
        end

        nil
      end

      def run_rspec(mutation)
        # When used via the Runner with Isolation::Fork, each mutation is executed
        # in its own forked child process, so RSpec state (loaded example groups,
        # world, configuration) cannot accumulate across mutation runs — the child
        # process exits after each run.
        #
        # This integration can also be invoked directly (e.g. in specs or alternative
        # runners) without fork isolation. RSpec.reset is called here as
        # defense-in-depth to clear RSpec state between mutation runs in those cases.
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
        expanded = File.expand_path(source_path)

        # Derive spec/ from mutation's project, not CWD
        if expanded.include?("/lib/")
          project_root = expanded.split(%r{/lib/}, 2).first
          spec_dir = File.join(project_root, "spec")
          return spec_dir if Dir.exist?(spec_dir)
        end

        # Walk up from the file's directory looking for spec/
        dir = File.dirname(expanded)
        loop do
          spec_dir = File.join(dir, "spec")
          return spec_dir if Dir.exist?(spec_dir)

          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end

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
