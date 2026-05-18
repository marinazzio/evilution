class Admin < User
  def admin?
    true
  end

  def role
    "admin"
  end
end

class PlainClass
  def no_parent
    42
  end
end

class Service < ActiveRecord::Base
  def save
    :ok
  end
end

class WithConstant < User
  TABLE = :records

  def lookup
    TABLE
  end
end

class Outer < User
  class Inner < User
    def inner_method
      :inner
    end
  end
end
