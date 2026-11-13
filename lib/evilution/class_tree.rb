# frozen_string_literal: true

require_relative "version"

# The classes below a class, reached through each class's own list of
# subclasses.
#
# ObjectSpace.each_object(Class) finds them too, but by walking the whole
# heap: every object of the process is visited to pick out the classes. In a
# forked mutation process that is every page the child shares with its
# parent, which the walk forces it to map; under Rails, millions of objects
# for every mutation. The class tree holds only the classes.
#
# Singleton classes are not in it, which is what every caller wants.
#
# Class#subclasses is called through an UnboundMethod: a class may define a
# `subclasses` of its own, which need not answer the question asked here.
module Evilution::ClassTree
  SUBCLASSES = Class.instance_method(:subclasses)
  private_constant :SUBCLASSES

  # Every class below `root`, at any depth; `root` itself is left out.
  def self.descendants(root)
    found = []
    visit(root) { |klass| found << klass }
    found.shift
    found
  end

  # Yields `root`, then the classes below it, each before its own
  # subclasses. Where the block answers falsy, the classes below the one it
  # was given are passed over.
  def self.visit(root, &block)
    return unless yield(root)

    SUBCLASSES.bind_call(root).each { |klass| visit(klass, &block) }
  end
end
