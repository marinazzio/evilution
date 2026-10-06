# frozen_string_literal: true

require_relative "../result"

# The survivors one red spec file turned neutral, with why it was red.
#
# spec_file is nil when the run was given its spec files explicitly: a survivor
# is then neutral whichever of them was red, so failures holds all of them.
Evilution::Result::BaselineNeutralization = Data.define(:spec_file, :count, :failures)
