# frozen_string_literal: true

class Evilution::RelatedSpecHeuristic
  RELATED_SPEC_DIRS = %w[
    spec/requests
    spec/integration
    spec/features
    spec/system
  ].freeze

  INCLUDES_PATTERN = /\bincludes\(/

  def call(mutation)
    return [] unless includes_mutation?(mutation)

    domain = extract_domain(mutation.file_path)
    return [] unless domain

    find_related_specs(domain)
  end

  private

  def includes_mutation?(mutation)
    diff = mutation.diff
    return false unless diff

    diff.split("\n").any? { |line| line.start_with?("- ") && line.match?(INCLUDES_PATTERN) }
  end

  def extract_domain(file_path)
    normalized = normalize_path(file_path)

    # Strip common prefixes and get the relative path under app/ or lib/
    relative = normalized
               .delete_prefix("app/controllers/")
               .delete_prefix("app/models/")
               .delete_prefix("app/")
               .delete_prefix("lib/")

    # Remove .rb extension and _controller suffix
    basename = relative.sub(/\.rb\z/, "")
    basename = basename.sub(/_controller\z/, "")

    basename.empty? ? nil : basename
  end

  def normalize_path(path)
    path = path.delete_prefix("./")
    path = path.delete_prefix("#{Dir.pwd}/") if path.start_with?("/")
    path
  end

  def find_related_specs(domain)
    RELATED_SPEC_DIRS.flat_map { |dir| find_specs_in_dir(dir, domain) }.sort
  end

  def find_specs_in_dir(dir, domain)
    return [] unless Dir.exist?(dir)

    Dir.glob(File.join(dir, "**", "#{domain}_spec.rb"))
  end
end
