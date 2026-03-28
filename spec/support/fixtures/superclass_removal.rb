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
