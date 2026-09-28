# frozen_string_literal: true

require_relative "base"

# `warmup: rails` warms Rails' lazily-initialised state in the parent after
# the preload; `none` (the default) skips it. `false` is accepted as `none`
# so `warmup: false` reads naturally in .evilution.yml.
class Evilution::Config::Validators::Warmup < Evilution::Config::Validators::Base
  ALLOWED = %i[none rails].freeze

  def self.call(value)
    return :none if value == false

    coerce_symbol!(value, allowed: ALLOWED, name: "warmup")
  end
end
