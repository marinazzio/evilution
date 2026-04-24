# frozen_string_literal: true

require_relative "../loading"

# Evaluate source with __FILE__ set to the absolute original path so that
# `require_relative` and `__dir__` resolve against the real source tree, where
# sibling files actually exist.
class Evilution::Integration::Loading::SourceEvaluator
  def call(source, file_path)
    absolute = File.expand_path(file_path)
    # rubocop:disable Security/Eval
    eval(source, TOPLEVEL_BINDING, absolute, 1)
    # rubocop:enable Security/Eval
  end
end
