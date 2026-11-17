# frozen_string_literal: true

# Reached only through the class that includes it, Greeting is tested here.
class Person
  include Greeting

  attr_reader :name

  def initialize(name)
    @name = name
  end
end
