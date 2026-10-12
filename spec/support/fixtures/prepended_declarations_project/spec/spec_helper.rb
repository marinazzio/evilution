# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "aasm"
# Re-declaring an event makes AASM log that it overrides the event's methods.
AASM::Configuration.hide_warnings = true
require "order"
