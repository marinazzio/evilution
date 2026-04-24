# frozen_string_literal: true

require_relative "../loading"
require_relative "../../ast/constant_names"

# Defeat Zeitwerk's re-autoload hook when we re-eval a file in place. Walking
# the source AST for top-level class/module names and calling `const_get` on
# each tells Zeitwerk "this constant is loaded" so our re-eval does not lose
# state (e.g. `@_included_block`) to a follow-up autoload.
class Evilution::Integration::Loading::ConstantPinner
  def initialize(constant_names: Evilution::AST::ConstantNames.new)
    @constant_names = constant_names
  end

  def call(source)
    names = @constant_names.call(source)
    names.each do |name|
      Object.const_get(name) if Object.const_defined?(name, false)
    rescue NameError # :nodoc:
      nil
    end
    names
  end
end
