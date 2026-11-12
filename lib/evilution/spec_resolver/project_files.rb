# frozen_string_literal: true

require_relative "../spec_resolver"

# Project-relative filesystem lookups shared by the spec resolver and its
# collaborators. Each lookup succeeds against the current CWD; when the caller
# is an isolated worker chdir'd into a per-mutation sandbox (signalled by
# Evilution.in_isolated_worker?), it also tries PROJECT_ROOT so the sandbox CWD
# does not break resolution. The PROJECT_ROOT fallback stays gated on that flag
# so a caller that chdirs on purpose (e.g. a fixture project) never resolves
# into the evilution dev tree.
module Evilution::SpecResolver::ProjectFiles
  module_function

  def exist?(path)
    return true if File.exist?(path)
    return false unless Evilution.in_isolated_worker?

    File.exist?(File.expand_path(path, Evilution::PROJECT_ROOT))
  end

  def directory?(path)
    return true if File.directory?(path)
    return false unless Evilution.in_isolated_worker?

    File.directory?(File.expand_path(path, Evilution::PROJECT_ROOT))
  end

  # base: PROJECT_ROOT yields paths relative to the root, matching the shape
  # of a CWD glob.
  def glob(pattern)
    return Dir.glob(pattern) unless Evilution.in_isolated_worker?

    Dir.glob(pattern, base: Evilution::PROJECT_ROOT)
  end

  # Raw bytes of the file, or "" when it is missing or unreadable. Binary so a
  # file with invalid UTF-8 cannot raise during an ASCII-only regex scan.
  def read(path)
    File.binread(locate(path))
  rescue SystemCallError
    ""
  end

  def locate(path)
    return path if File.exist?(path) || !Evilution.in_isolated_worker?

    File.expand_path(path, Evilution::PROJECT_ROOT)
  end
end
