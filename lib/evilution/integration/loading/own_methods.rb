# frozen_string_literal: true

require_relative "../loading"

# The methods a class defined itself, held while a concern's hook block is run
# on it a second time.
#
# The first time, the block ran when the class took the concern, and whatever
# the class went on to define under the same name replaced the block's method.
# Run again, the block would put its own back in that place: code that is dead
# for the class would come alive, and its tests would fail whatever the mutant.
#
# A method counts as the class's own when it was not written in the block's
# file. One that is found written there afterwards was replaced by the block,
# and is put back. A class that defines such a method in the concern's own file
# cannot be told apart and is not protected.
class Evilution::Integration::Loading::OwnMethods
  # Called through UnboundMethods: a class may define any of these for its
  # own purposes.
  PUBLIC = Module.instance_method(:public_instance_methods)
  PROTECTED = Module.instance_method(:protected_instance_methods)
  PRIVATE = Module.instance_method(:private_instance_methods)
  LOOKUP = Module.instance_method(:instance_method)
  DEFINED = Module.instance_method(:method_defined?)
  PRIVATELY_DEFINED = Module.instance_method(:private_method_defined?)
  DEFINE = Module.instance_method(:define_method)
  SINGLETON_CLASS = Kernel.instance_method(:singleton_class)
  VISIBILITIES = { public: PUBLIC, protected: PROTECTED, private: PRIVATE }.freeze
  SETTERS = VISIBILITIES.keys.to_h { |visibility| [visibility, Module.instance_method(visibility)] }.freeze
  private_constant :PUBLIC, :PROTECTED, :PRIVATE, :LOOKUP, :DEFINED, :PRIVATELY_DEFINED, :DEFINE, :SINGLETON_CLASS,
                   :VISIBILITIES, :SETTERS

  Kept = Struct.new(:owner, :name, :definition, :visibility)
  private_constant :Kept

  # Runs the block, then puts back the methods of `klass` that the code of
  # `file` replaced meanwhile -- also when the block raises.
  def self.keeping(klass, file)
    own = new(klass, file)
    begin
      yield
    ensure
      own.put_back
    end
  end

  def initialize(klass, file)
    @file = file
    @kept = [klass, SINGLETON_CLASS.bind_call(klass)].flat_map { |owner| own_methods_of(owner) }
  end

  def put_back
    @kept.each { |kept| restore(kept) if replaced?(kept) }
  end

  private

  def own_methods_of(owner)
    VISIBILITIES.flat_map do |visibility, list|
      list.bind_call(owner, false).filter_map do |name|
        definition = LOOKUP.bind_call(owner, name)
        Kept.new(owner, name, definition, visibility) unless written_in_file?(definition)
      end
    end
  end

  def written_in_file?(definition)
    location = definition.source_location
    !location.nil? && location.first == @file
  end

  # A method the block removed stays removed.
  def replaced?(kept)
    return false unless defined_on?(kept.owner, kept.name)

    written_in_file?(LOOKUP.bind_call(kept.owner, kept.name))
  end

  def defined_on?(owner, name)
    DEFINED.bind_call(owner, name) || PRIVATELY_DEFINED.bind_call(owner, name)
  end

  def restore(kept)
    DEFINE.bind_call(kept.owner, kept.name, kept.definition)
    SETTERS.fetch(kept.visibility).bind_call(kept.owner, kept.name)
  end
end
