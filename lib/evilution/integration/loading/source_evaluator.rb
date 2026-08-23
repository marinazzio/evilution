# frozen_string_literal: true

require_relative "../loading"

# Evaluate source with __FILE__ set to the absolute original path so that
# `require_relative` and `__dir__` resolve against the real source tree, where
# sibling files actually exist.
#
# Trust boundary: `source` is never user-supplied. It is always the original
# on-disk source from a file the user already pointed Evilution at, with
# byte-level mutations applied by AST::SourceSurgeon. The only difference
# between this eval path and a plain `require` of the same file is that we
# substitute the mutated bytes — the privilege level is identical.
class Evilution::Integration::Loading::SourceEvaluator
  def call(source, file_path)
    # When the isolator has chdir'd into a per-mutation sandbox (EV-wqxu /
    # GH #1278), anchor the eval __FILE__ against PROJECT_ROOT so siblings
    # `require_relative` can find each other from the real source tree.
    absolute = File.expand_path(file_path, Evilution.project_base_dir)
    without_ruby_warnings { eval(source, TOPLEVEL_BINDING, absolute, 1) }
  end

  private

  # Re-evaluating a file necessarily redefines its methods and reassigns its
  # constants, so in verbose mode Ruby emits "method redefined; discarding
  # old ..." and "already initialized constant ...". Those describe how
  # evilution applies a mutation, not anything about the code under test.
  #
  # They are not merely noise. A project that runs its suite with warnings on
  # AND promotes them to exceptions -- dry-schema's `.rspec` carries
  # `--warnings` while its spec_helper installs `Warning.process { |w| raise w }`
  # -- turns every one of them into a failure, so every mutation is scored
  # :error. dry-schema measured 262 errors out of 263 mutations that way.
  #
  # Suppression is scoped to the eval itself and restored on the way out, so
  # warnings raised while the tests actually run are unaffected: a suite that
  # asserts on its own warnings still sees them.
  # EV-df7u / GH #1588.
  def without_ruby_warnings
    previous = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous
  end
end
