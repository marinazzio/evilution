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
    @sibling_ranker = SiblingSpecRanker.new(test_suffix: test_suffix)
  end

  # Resolution order, first hit wins: the 1:1 mirror file, then the best
  # related test among the siblings in the source's own mirror directory, then
  # the parent directories' tests and the non-mirrored naming conventions.
  def call(source_path, spec_pattern: nil)
    return nil if source_path.nil? || source_path.empty?

    normalized = normalize_path(source_path)
    first_existing(primary_candidates(normalized), spec_pattern) ||
      sibling_specs(normalized, spec_pattern).first ||
      first_existing(fallback_candidates(normalized), spec_pattern)
  end

  def resolve_all(source_paths)
    Array(source_paths).filter_map { |path| call(path) }.uniq
  end

  # Like #call, but returns an ARRAY of test files: every related sibling test
  # (ranked) instead of only the best one, and additionally the dir-grouped
  # layout (a source file's tests live in a directory named after the source
  # basename, e.g. lib/x/branch.rb -> test/unit/branch/*_test.rb, rather than a
  # single mirror file). Whatever #call would pick always wins; only when it
  # finds nothing is the first matching grouped directory expanded into its
  # test files (EV-bi41). Returns nil when nothing resolves.
  def resolve_specs(source_path, spec_pattern: nil)
    return nil if source_path.nil? || source_path.empty?

    normalized = normalize_path(source_path)
    mirror = first_existing(primary_candidates(normalized), spec_pattern)
    return [mirror] if mirror

    siblings = sibling_specs(normalized, spec_pattern)
    return siblings unless siblings.empty?

    fallback = first_existing(fallback_candidates(normalized), spec_pattern)
    return [fallback] if fallback

    resolve_grouped_dir(normalized, spec_pattern: spec_pattern)
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

    suggestion_globs(stem).flat_map { |glob| ProjectFiles.glob(glob) }.uniq.min_by(&:length)
  end

  private

  def first_existing(candidates, spec_pattern)
    candidates = filter_by_pattern(candidates, spec_pattern) if spec_pattern
    candidates.find { |path| ProjectFiles.exist?(path) }
  end

  # Related tests among the direct children of the source's mirror
  # directories, ranked by SiblingSpecRanker. Only nested sources have a mirror
  # directory of their own: the bare-basename variant is skipped, so the test
  # root itself is never scanned.
  def sibling_specs(normalized, spec_pattern)
    variants = mirror_variants(strip_source_prefix(normalized)).select { |variant| variant.include?("/") }
    dirs = variants.flat_map { |variant| roots.map { |root| "#{root}/#{File.dirname(variant)}" } }
    specs = @sibling_ranker.call(normalized, dirs.uniq.select { |dir| ProjectFiles.directory?(dir) })
    spec_pattern ? filter_by_pattern(specs, spec_pattern) : specs
  end

  def suggestion_globs(stem)
    globs = ["#{@test_dir}/**/*#{stem}*#{@test_suffix}"]
    globs << "#{@test_dir}/**/test_#{stem}.rb" if @test_suffix == MINITEST_SUFFIX
    globs
  end

  def filter_by_pattern(candidates, pattern)
    candidates.select { |path| File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
  end

  # Dir-grouped resolution: find the first candidate directory that exists and
  # expand it into its test files. Ranked below #call's file mirrors (callers
  # try #call first), so a 1:1 spec always wins when present.
  def resolve_grouped_dir(normalized, spec_pattern: nil)
    dir = directory_candidates(normalized).find { |c| ProjectFiles.directory?(c) }
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
    globs.compact.flat_map { |glob| ProjectFiles.glob(glob) }.uniq.sort
  end

  def normalize_path(path)
    path = path.delete_prefix("./")
    if path.start_with?("/")
      path = path.delete_prefix("#{Dir.pwd}/")
      path = path.delete_prefix("#{Evilution::PROJECT_ROOT}/") if Evilution.in_isolated_worker?
    end
    path
  end

  # The 1:1 mirrors of the source (plus the controller -> request mapping).
  def primary_candidates(source_path)
    stripped = strip_source_prefix(source_path)
    primary = mirror_candidates(stripped)
    primary.unshift(controller_to_request_test(stripped)) if STRIPPABLE_PREFIXES.any? { |p| source_path.start_with?(p) }
    primary.compact
  end

  # Ranked below the mirrors and the related sibling tests: the parent
  # directories' tests, then the non-mirrored naming conventions.
  def fallback_candidates(source_path)
    parents = primary_candidates(source_path).flat_map { |c| parent_fallback_candidates(c) }
    (parents + convention_candidates(strip_source_prefix(source_path))).uniq
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
  # Built from the FULL lib-relative path only (every segment joined with `_`),
  # NOT from namespace-dropped variants — dropping segments would yield bare
  # basename forms (test_timed_stack.rb) that collide across namespaces and are
  # already covered by #prefix_convention_candidates. Top-level sources have no
  # namespace to flatten, so they produce nothing here. Ranked below the mirrored
  # layouts (appended last) so a 1:1 file always wins. Minitest suffix only.
  def flat_prefixed_candidates(stripped)
    return [] unless @test_suffix == MINITEST_SUFFIX
    return [] unless stripped.include?("/")

    name = stripped.delete_suffix(@test_suffix).tr("/", "_")
    return [] if name.empty?

    roots.map { |root| "#{root}/test_#{name}.rb" }
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

require_relative "spec_resolver/project_files"
require_relative "spec_resolver/sibling_spec_ranker"
