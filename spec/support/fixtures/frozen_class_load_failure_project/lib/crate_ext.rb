# frozen_string_literal: true

# Reopens a class another file defines. A mutant that freezes the class here
# makes the rest of this body raise; evaluating this file alone into a fresh
# class gives one without the methods crate.rb defines.
class Crate
  LABEL = Crate.name.freeze

  def empty?
    size.zero?
  end
end
