# frozen_string_literal: true

require_relative "../ast"

# Named presets of code whose mutations are rarely worth a test run: log
# lines, debug output, the messages of raised errors, load-time requires.
# Each preset is a structural rule over the Prism tree (see SkipSites::Presets).
module Evilution::AST::SkipSites
end
