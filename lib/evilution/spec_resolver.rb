# frozen_string_literal: true

class Evilution::SpecResolver
  STRIPPABLE_PREFIXES = %w[lib/ app/].freeze
  CONTROLLER_PREFIX = "controllers/"

  def initialize(test_dir: "spec", test_suffix: "_spec.rb", request_dir: "requests")
    @test_dir = test_dir
    @test_suffix = test_suffix
    @request_dir = request_dir
  end

  def call(source_path)
    return nil if source_path.nil? || source_path.empty?

    normalized = normalize_path(source_path)
    candidates = candidate_test_paths(normalized)
    candidates.find { |path| File.exist?(path) }
  end

  def resolve_all(source_paths)
    Array(source_paths).filter_map { |path| call(path) }.uniq
  end

  private

  def normalize_path(path)
    path = path.delete_prefix("./")
    path = path.delete_prefix("#{Dir.pwd}/") if path.start_with?("/")
    path
  end

  def candidate_test_paths(source_path)
    base = source_path.sub(/\.rb\z/, @test_suffix)
    prefix = STRIPPABLE_PREFIXES.find { |p| source_path.start_with?(p) }

    candidates = if prefix
                   stripped = base.delete_prefix(prefix)
                   request_test = controller_to_request_test(stripped)
                   [request_test, "#{@test_dir}/#{stripped}", "#{@test_dir}/#{base}"].compact
                 else
                   ["#{@test_dir}/#{base}"]
                 end

    fallbacks = candidates.flat_map { |c| parent_fallback_candidates(c) }.uniq

    candidates + fallbacks
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
