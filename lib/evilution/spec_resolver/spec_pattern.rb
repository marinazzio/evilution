# frozen_string_literal: true

require_relative "../spec_resolver"

# The `spec_pattern` glob a run may narrow test files with. Shared by the
# resolver and the sibling ranker so both apply the same matching rules, and so
# the ranker can drop excluded files before reading them.
module Evilution::SpecResolver::SpecPattern
  FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

  module_function

  # Paths unchanged when pattern is nil.
  def filter(paths, pattern)
    return paths unless pattern

    paths.select { |path| File.fnmatch?(pattern, path, FLAGS) }
  end
end
