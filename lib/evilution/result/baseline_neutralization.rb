# frozen_string_literal: true

require_relative "../result"

# The kills one red spec file left uncounted -- mutations whose tests failed
# on nothing but examples that were already failing -- with why it was red.
#
# spec_file is nil when no single red file can be named, as in a run given
# its spec files explicitly; failures then holds all of them.
Evilution::Result::BaselineNeutralization = Data.define(:spec_file, :count, :failures)
