# frozen_string_literal: true

class Evilution::SpecResolver
  STRIPPABLE_PREFIXES = %w[lib/ app/].freeze
  CONTROLLER_PREFIX = "controllers/"
  # Conventional test subdirectories appended to @test_dir. Real-world gems
  # frequently park specs under spec/unit or spec/lib (test/unit, test/lib)
  # rather than mirroring the lib/ tree 1:1 (EV-z7f5 / GH #1325).
  CONVENTIONAL_SUBDIRS = %w[unit lib].freeze
  MINITEST_SUFFIX = "_test.rb"

  def initialize(test_dir: "spec", test_suffix: "_spec.rb", request_dir: "requests")
    @test_dir = test_dir
    @test_suffix = test_suffix
    @request_dir = request_dir
  end

  def call(source_path, spec_pattern: nil)
    return nil if source_path.nil? || source_path.empty?

    normalized = normalize_path(source_path)
    candidates = candidate_test_paths(normalized)
    candidates = filter_by_pattern(candidates, spec_pattern) if spec_pattern
    candidates.find { |path| project_relative_exists?(path) }
  end

  def resolve_all(source_paths)
    Array(source_paths).filter_map { |path| call(path) }.uniq
  end

  # Like #call, but returns an ARRAY of test files and additionally covers the
  # dir-grouped layout (a source file's tests live in a directory named after
  # the source basename, e.g. lib/x/branch.rb -> test/unit/branch/*_test.rb,
  # rather than a single mirror file). The deterministic file mirror from #call
  # always wins; only when no mirror file exists is the first matching grouped
  # directory expanded into its test files (EV-bi41). Returns nil when nothing
  # resolves.
  def resolve_specs(source_path, spec_pattern: nil)
    return nil if source_path.nil? || source_path.empty?

    file = call(source_path, spec_pattern: spec_pattern)
    return [file] if file

    resolve_grouped_dir(source_path, spec_pattern: spec_pattern)
  end

  # Best-guess candidate for an unresolved source, found by basename glob
  # rather than the deterministic path mirroring used by #call. Used only to
  # enrich the "no matching test" hint (EV-z7f5 / GH #1325) — never to pick a
  # test to run — so a fuzzy substring match is acceptable here. Returns the
  # shallowest match, or nil when nothing resembles the basename.
  def suggest(source_path)
    return nil if source_path.nil? || source_path.empty?

    stem = File.basename(normalize_path(source_path), ".rb")
    return nil if stem.empty?

    suggestion_globs(stem).flat_map { |glob| glob_relative(glob) }.uniq.min_by(&:length)
  end

  private

  # Glob for project-relative paths. Mirrors #call's project_relative_exists?
  # contract: when run inside an isolated worker chdir'd into a sandbox, glob
  # against PROJECT_ROOT so suggestions still find real project files. base:
  # already yields paths relative to the root, matching the CWD-glob shape.
  def glob_relative(glob)
    return Dir.glob(glob) unless Evilution.in_isolated_worker?

    Dir.glob(glob, base: Evilution::PROJECT_ROOT)
  end

  def suggestion_globs(stem)
    globs = ["#{@test_dir}/**/*#{stem}*#{@test_suffix}"]
    globs << "#{@test_dir}/**/test_#{stem}.rb" if @test_suffix == MINITEST_SUFFIX
    globs
  end

  # Existence check that succeeds against the current CWD. When the caller
  # is an isolated worker that chdir'd into a per-mutation sandbox (Evilution
  # signals this via in_isolated_worker?), also try PROJECT_ROOT so the
  # sandbox CWD does not break spec resolution (EV-wqxu / GH #1278).
  def project_relative_exists?(path)
    return true if File.exist?(path)
    return false unless Evilution.in_isolated_worker?

    File.exist?(File.expand_path(path, Evilution::PROJECT_ROOT))
  end

  def filter_by_pattern(candidates, pattern)
    candidates.select { |path| File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
  end

  # Dir-grouped resolution: find the first candidate directory that exists and
  # expand it into its test files. Ranked below #call's file mirrors (callers
  # try #call first), so a 1:1 spec always wins when present.
  def resolve_grouped_dir(source_path, spec_pattern: nil)
    dir = directory_candidates(normalize_path(source_path)).find { |c| project_relative_dir?(c) }
    return nil unless dir

    files = test_files_in(dir)
    files = filter_by_pattern(files, spec_pattern) if spec_pattern
    files.empty? ? nil : files
  end

  # The grouped-directory analogue of #mirror_candidates: cross every
  # conventional root with each layout variant, using the source basename
  # (suffix dropped) as a DIRECTORY name rather than a test FILE name.
  def directory_candidates(source_path)
    stripped = strip_source_prefix(source_path)
    mirror_variants(stripped).flat_map { |variant| grouped_dir_candidates(variant) }.uniq
  end

  def grouped_dir_candidates(variant)
    dir, _, file = variant.rpartition("/")
    name = file.delete_suffix(@test_suffix)
    return [] if name.empty?

    relative = dir.empty? ? name : "#{dir}/#{name}"
    roots.map { |root| "#{root}/#{relative}" }
  end

  def strip_source_prefix(source_path)
    base = source_path.sub(/\.rb\z/, @test_suffix)
    prefix = STRIPPABLE_PREFIXES.find { |p| source_path.start_with?(p) }
    prefix ? base.delete_prefix(prefix) : base
  end

  # Every test file under a grouped directory: the mirrored suffix plus, for
  # minitest/test-unit, the `test_` prefix convention. Sorted for determinism.
  def test_files_in(dir)
    globs = ["#{dir}/**/*#{@test_suffix}", ("#{dir}/**/test_*.rb" if @test_suffix == MINITEST_SUFFIX)]
    globs.compact.flat_map { |glob| glob_relative(glob) }.uniq.sort
  end

  # Directory analogue of #project_relative_exists?.
  def project_relative_dir?(path)
    return true if File.directory?(path)
    return false unless Evilution.in_isolated_worker?

    File.directory?(File.expand_path(path, Evilution::PROJECT_ROOT))
  end

  def normalize_path(path)
    path = path.delete_prefix("./")
    if path.start_with?("/")
      path = path.delete_prefix("#{Dir.pwd}/")
      path = path.delete_prefix("#{Evilution::PROJECT_ROOT}/") if Evilution.in_isolated_worker?
    end
    path
  end

  def candidate_test_paths(source_path)
    base = source_path.sub(/\.rb\z/, @test_suffix)
    prefix = STRIPPABLE_PREFIXES.find { |p| source_path.start_with?(p) }
    stripped = prefix ? base.delete_prefix(prefix) : base

    primary = mirror_candidates(stripped)
    primary.unshift(controller_to_request_test(stripped)) if prefix
    primary.compact!

    fallbacks = primary.flat_map { |c| parent_fallback_candidates(c) }

    (primary + fallbacks + convention_candidates(stripped)).uniq
  end

  # Non-mirrored Test::Unit/minitest filename conventions: the `test_<name>.rb`
  # prefix and the flat namespace-prefixed form. Both rank below the mirrored
  # layouts assembled in #candidate_test_paths.
  def convention_candidates(stripped)
    prefix_convention_candidates(stripped) + flat_prefixed_candidates(stripped)
  end

  # Conventional roots that may hold tests: the mirrored root plus the common
  # spec/unit, spec/lib (test/unit, test/lib) buckets.
  def roots
    [@test_dir, *CONVENTIONAL_SUBDIRS.map { |d| "#{@test_dir}/#{d}" }]
  end

  # Cross every conventional root with every layout variant of the stripped
  # source path: the full mirror, the mirror with the leading gem-namespace
  # dir dropped, and the bare basename. Full mirrors rank above dropped ones
  # so a 1:1 layout always wins when present.
  def mirror_candidates(stripped)
    mirror_variants(stripped).flat_map do |variant|
      roots.map { |root| "#{root}/#{variant}" }
    end
  end

  def mirror_variants(stripped)
    segments = stripped.split("/")
    variants = [stripped]
    variants << segments[1..].join("/") if segments.length > 1
    variants << segments.last if segments.length > 2
    variants.uniq
  end

  # Test::Unit / minitest gems frequently name files with a `test_` PREFIX
  # (test/test_connection_pool.rb) instead of the mirrored `_test.rb` suffix.
  # Only meaningful when resolving against the minitest suffix.
  def prefix_convention_candidates(stripped)
    return [] unless @test_suffix == MINITEST_SUFFIX

    mirror_variants(stripped).flat_map do |variant|
      dir, _, file = variant.rpartition("/")
      name = file.delete_suffix(@test_suffix)
      next [] if name.empty?

      relative = dir.empty? ? "test_#{name}.rb" : "#{dir}/test_#{name}.rb"
      roots.map { |root| "#{root}/#{relative}" }
    end
  end

  # Test::Unit / minitest gems sometimes flatten a nested source's path into a
  # single `test_`-prefixed file at the test root: lib/connection_pool/timed_stack.rb
  # -> test/test_connection_pool_timed_stack.rb (no test/connection_pool/ subdir).
  # The lib-relative path is joined with underscores and prefixed with `test_`.
  # Ranked below the mirrored layouts (appended last) so a 1:1 file always wins.
  # Only meaningful against the minitest suffix.
  def flat_prefixed_candidates(stripped)
    return [] unless @test_suffix == MINITEST_SUFFIX

    mirror_variants(stripped).flat_map do |variant|
      name = variant.delete_suffix(@test_suffix).tr("/", "_")
      next [] if name.empty?

      roots.map { |root| "#{root}/test_#{name}.rb" }
    end.uniq
  end

  def controller_to_request_test(stripped_path)
    return nil unless stripped_path.start_with?(CONTROLLER_PREFIX)

    controller_suffix = "_controller#{@test_suffix}"
    return nil unless stripped_path.end_with?(controller_suffix)

    request_path = stripped_path
                   .delete_prefix(CONTROLLER_PREFIX)
                   .sub(/#{Regexp.escape(controller_suffix)}\z/, @test_suffix)
    "#{@test_dir}/#{@request_dir}/#{request_path}"
  end

  def parent_fallback_candidates(test_path)
    parts = test_path.split("/")
    # parts: ["spec", "foo", "bar_spec.rb"] — need at least 3 parts for fallback
    return [] if parts.length < 3

    candidates = []
    # Remove filename, then progressively remove directories
    dir_parts = parts[1..-2]

    (dir_parts.length - 1).downto(0) do |i|
      file = "#{dir_parts[i]}#{@test_suffix}"

      if i.zero?
        candidates << "#{@test_dir}/#{file}"
      else
        parent = dir_parts[0...i].join("/")
        candidates << "#{@test_dir}/#{parent}/#{file}"
      end
    end

    candidates
  end
end
