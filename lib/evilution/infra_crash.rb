# frozen_string_literal: true

require_relative "version"

# The crash classes that come from the test infrastructure (a timed-out or
# locked database, a slow CI) rather than from the mutation, so a test that
# crashes on one says nothing about the mutation.
#
# Shared by the integrations, which must not stop a run on such a crash, and
# by the runner, which neutralises and retries mutations killed by one. Needs
# only the top-level namespace: the integrations load it while evilution
# itself is still loading.
module Evilution::InfraCrash
  CLASSES = %w[
    Timeout::Error
    ActiveRecord::StatementTimeout
    ActiveRecord::Deadlocked
    ActiveRecord::ConnectionTimeoutError
    ActiveRecord::LockWaitTimeout
    SQLite3::BusyException
  ].freeze

  def self.class_name?(error_class)
    CLASSES.include?(error_class)
  end
end
