# frozen_string_literal: true

require "active_model"

# Just enough of a model for a concern to declare on: validations with
# callbacks, a `scope` that defines a class method running its body against
# the class, and `track`, standing in for a declaration that must not run
# twice.
class Record
  include ActiveModel::Model
  include ActiveModel::Validations::Callbacks

  attr_accessor :total, :paid, :rush, :address, :express, :courier, :steps

  def initialize(attributes = {})
    super
    @steps = []
  end

  def self.scope(name, body)
    define_singleton_method(name) { |*args| instance_exec(*args, &body) }
  end

  def self.track(name)
    tracked << name
  end

  def self.tracked
    @tracked ||= []
  end

  def self.rows
    [{ title: "draft", published: false }, { title: "live", published: true }]
  end
end
