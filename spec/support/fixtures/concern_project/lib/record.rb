# frozen_string_literal: true

# Just enough of a model to declare scopes on: `scope` defines a class method
# running its body against the class, and `track` appends to a list, standing
# in for the declarations that must not run twice (validations, callbacks).
class Record
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
