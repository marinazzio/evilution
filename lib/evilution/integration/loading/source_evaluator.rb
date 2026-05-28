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
    eval(source, TOPLEVEL_BINDING, absolute, 1)
  end
end
