# frozen_string_literal: true

require_relative "../../integration"

# Mirrors `ruby -Itest` / `-Ispec` for in-process test loading.
#
# evilution loads resolved test files with Kernel#load instead of shelling out,
# so the `-Itest` shown in the displayed command string is never actually
# applied to $LOAD_PATH. Minitest and Test::Unit suites near-universally
# `require "test_helper"` (which the suite's own runner satisfies via -Itest);
# without the test root on $LOAD_PATH that bare require raises LoadError and
# every mutation errors with score 0.0 (EV-52hf / GH #1326).
#
# Anchors against Evilution.project_base_dir, which resolves to PROJECT_ROOT
# inside an isolated worker (EV-wqxu / GH #1278) and Dir.pwd otherwise, so the
# same call works on both the baseline (parent) and mutation (child) paths.
module Evilution::Integration::Loading::TestLoadPath
  ROOT_NAMES = %w[test spec].freeze

  module_function

  # Prepend every relevant test directory to $LOAD_PATH (idempotently).
  def add!(files, base: Evilution.project_base_dir)
    dirs_for(files, base).each do |dir|
      $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
    end
  end

  # The directories to put on $LOAD_PATH for the given resolved test files:
  # the conventional test/ and spec/ roots under base, each file's own
  # directory, and the topmost test/spec ancestor of each file (covers nested
  # layouts like test/unit, spec/lib, spec/unit). Existing directories only,
  # and only those inside the project base -- never a broad outside-project dir
  # (e.g. a /tmp test file), which would over-widen $LOAD_PATH for the whole
  # process (the baseline runs in the long-lived parent).
  def dirs_for(files, base)
    base = File.expand_path(base)
    dirs = conventional_roots(base)
    Array(files).each do |file|
      file_dir = File.dirname(File.expand_path(file, base))
      dirs << file_dir
      root = root_ancestor(file_dir, base)
      dirs << root if root
    end
    dirs.uniq.select { |dir| File.directory?(dir) && within?(dir, base) }
  end

  def within?(dir, base)
    dir == base || dir.start_with?("#{base}/")
  end

  def conventional_roots(base)
    ROOT_NAMES.map { |name| File.join(base, name) }
  end

  # Walk from `dir` up to `base`, returning the highest ancestor whose basename
  # is a conventional test root (test/spec). Highest, so test/unit/foo_test.rb
  # yields `test` (matching -Itest), not the intermediate test/unit.
  def root_ancestor(dir, base)
    base = File.expand_path(base)
    found = nil
    current = File.expand_path(dir)
    loop do
      found = current if ROOT_NAMES.include?(File.basename(current))
      break if current == base

      parent = File.dirname(current)
      break if parent == current

      current = parent
    end
    found
  end
end
