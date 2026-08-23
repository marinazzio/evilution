# frozen_string_literal: true

require_relative "../evilution"

# Evilution's own advisory messages -- "no matching spec found", and the like.
#
# These deliberately bypass Kernel#warn. That routes through Warning.warn,
# which a project is free to replace: the `warning` gem with a raising handler
# turns every Ruby warning into an exception, and both dry-schema and
# dry-monads configure exactly that in their spec_helper. Under such a project
# our advisory message would be promoted to a fatal error, so a mutation we
# meant to classify :unresolved would be reported :error instead -- 239 of
# dry-monads' 240 mutations, in the run that found this.
#
# A message about how evilution is behaving must never be able to fail a
# user's mutation. Writing straight to the stream keeps it a diagnostic.
# EV-df7u / GH #1588.
module Evilution::Diagnostic
  def self.warn(message, stream: $stderr)
    stream.puts(message)
  end
end
