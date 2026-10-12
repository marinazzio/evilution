# frozen_string_literal: true

require "auditable"

class Journal
  def self.audits
    @audits ||= []
  end

  def self.audit(name)
    audits << name
  end

  prepend Auditable
end
