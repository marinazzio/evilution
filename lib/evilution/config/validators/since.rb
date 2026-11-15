# frozen_string_literal: true

require_relative "../validators"
require_relative "base"

# The git ref given as --since, stripped of the space around it; nil when none
# was given. The commands check it before git is asked about the ref, so that
# an empty ref or a conflicting target is reported as such rather than as a
# ref git does not know, or as a missing repository.
class Evilution::Config::Validators::Since < Evilution::Config::Validators::Base
  def self.call(value, target:)
    return nil if value.nil?

    ref = value.to_s.strip
    raise Evilution::ConfigError, "--since needs a git ref, such as main or origin/main" if ref.empty?
    return ref unless target.to_s.start_with?("source:")

    raise Evilution::ConfigError,
          "--since picks the changed files itself and cannot be combined with --target source:GLOB; " \
          "pass the files to limit it to instead"
  end
end
