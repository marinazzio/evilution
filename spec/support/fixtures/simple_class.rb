class User
  attr_reader :name, :age

  def initialize(name, age)
    @name = name
    @age = age
  end

  def adult?
    @age >= 18
  end

  def greeting
    "Hello, #{@name}"
  end
end

class Admin < User
  def admin?
    true
  end
end
