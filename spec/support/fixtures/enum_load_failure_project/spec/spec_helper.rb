# frozen_string_literal: true

# The model is autoloaded on first reference, as Rails loads one, so the
# process has not evaluated its file when evilution starts.
autoload :BreakdownMove, File.expand_path("../lib/breakdown_move", __dir__)
