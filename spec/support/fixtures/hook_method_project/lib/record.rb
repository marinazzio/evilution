# frozen_string_literal: true

class Record
  def self.tracked
    @tracked ||= []
  end

  def self.track(name)
    tracked << name
  end
end
