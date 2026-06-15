# frozen_string_literal: true

require_relative "../evilution"

# Per-example line-coverage support: build a `source file:line -> [examples]`
# map so mutation targeting can run exactly the examples that execute a line.
module Evilution::Coverage
end
