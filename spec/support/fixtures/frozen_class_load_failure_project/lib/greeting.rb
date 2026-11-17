# frozen_string_literal: true

# A module another file's class includes. A mutant that freezes the module
# here makes the rest of this body raise; a fresh module evaluated in its place
# is included by nothing.
module Greeting
  LABEL = Greeting.name.freeze

  def greet
    "Hello, #{name}"
  end

  def shout
    "#{greet.upcase}!"
  end
end
