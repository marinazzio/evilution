# frozen_string_literal: true

require_relative "../loading"

# Empties the anonymous modules an earlier evaluation of a file left behind.
#
# A file can install a module it never names:
#
#   handler = Module.new { def const_missing(name) = ... }
#   Object.extend(handler)
#
# Evaluating the file again builds a new module and extends with it again, and
# Ruby has no way to take the old one off. Under in-process isolation the file
# is evaluated for every mutation and every restore, so the modules pile up on
# their host, and a `super` in the mutation under test runs the code of every
# mutation before it. Its tests then fail on a predecessor's bug, and the
# mutation is reported killed. Fork isolation never sees this: a child holds
# one mutation.
#
# A module cannot be taken off, but its methods can be removed, and method
# lookup passes through a module that has none. So the modules created while a
# file is evaluated are remembered, and emptied when the same file is evaluated
# next.
#
# Two limits keep this to what the new evaluation really replaces. Only
# modules are emptied, not anonymous classes, whose instances may be held
# elsewhere. And only methods written in the file itself are removed: a module
# some library built on the file's behalf holds methods written in the
# library, which evaluating the file again does not define anew.
class Evilution::Integration::Loading::SupersededModules
  @registry = {}

  class << self
    # Created modules by file, for the process: the evaluations of one file
    # are not all made through the same instance.
    attr_reader :registry
  end

  MODULE_NAME = Module.instance_method(:name)
  INSTANCE_OF = Kernel.instance_method(:instance_of?)
  private_constant :MODULE_NAME, :INSTANCE_OF

  def initialize(registry: self.class.registry)
    @registry = registry
  end

  # Evaluates the block as an evaluation of `file_path`. The modules of the
  # evaluation before are emptied first, so that the new one starts from what
  # a fresh process would hold; the modules this one creates are remembered
  # whether or not it completes.
  #
  # A fork child holds one mutation and ends with it, so there is nothing for
  # it to empty later, and walking the heap of a process just forked is dear:
  # every page touched has to be mapped first. It evaluates and no more.
  def track(file_path)
    return yield if Evilution.single_mutation_process?

    retire(file_path)
    known = anonymous_modules
    yield
  ensure
    remember(file_path, known) if known
  end

  private

  # Nothing is kept for a file whose evaluation created none, which is most
  # files: an entry is only worth carrying when there is a module to empty.
  def remember(file_path, known)
    created = anonymous_modules.reject { |mod| known.key?(mod) }.keys
    @registry[file_path] = created unless created.empty?
  end

  def retire(file_path)
    Array(@registry.delete(file_path)).each { |mod| empty(mod, file_path) }
  end

  def empty(mod, file_path)
    return if mod.frozen?

    own = mod.instance_methods(false) + mod.private_instance_methods(false)
    own.each { |name| mod.send(:remove_method, name) if written_in?(mod.instance_method(name), file_path) }
  end

  def written_in?(method, file_path)
    location = method.source_location
    !location.nil? && location.first == file_path
  end

  # No message is sent to the modules walked. ObjectSpace yields everything
  # that is a Module, and some of it answers messages in its own way: a class
  # may define `name`, `hash` or `==` for itself, and ActiveSupport's
  # DeprecatedConstantProxy, a Module subclass, turns any message into a
  # deprecation, which a project may have set to raise. Hence the identity
  # keys and the methods bound from Module and Kernel.
  def anonymous_modules
    found = {}.compare_by_identity
    ObjectSpace.each_object(Module) do |mod|
      found[mod] = true if INSTANCE_OF.bind_call(mod, Module) && MODULE_NAME.bind_call(mod).nil?
    end
    found
  end
end
