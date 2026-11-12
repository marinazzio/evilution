# frozen_string_literal: true

require_relative "diagnostic"

# Points a forked parallel worker's ActiveRecord connection at the database
# config/database.yml resolves to for that worker.
#
# A preload boots the app in the parent, so database.yml is rendered once,
# before any worker exists, with the parent's TEST_ENV_NUMBER. A worker sets its
# own TEST_ENV_NUMBER only after the fork, too late for the already-resolved
# configuration: every worker would share the parent's database and see each
# other's writes. This re-renders database.yml in the worker and re-establishes
# the connection when the result differs.
#
# Only a connection that still matches the boot-time database.yml is replaced;
# one the app established by other means (an in-memory database set up in a
# test helper) is left alone. Evilution does not depend on Rails, so every
# reference is guarded. A failure is reported and the worker carries on with
# the inherited connection.
class Evilution::WorkerDatabase
  def self.reconnect(stream: $stderr)
    new(stream: stream).reconnect
  end

  def initialize(stream:)
    @stream = stream
  end

  def reconnect
    return unless reconnectable?

    current = base.connection_db_config
    refresh(current) if same_config?(base.configurations, current)
  rescue StandardError, ScriptError => e
    Evilution::Diagnostic.warn(
      "[evilution] worker database: kept the preloaded connection (#{e.class}: #{e.message})",
      stream: @stream
    )
  end

  private

  # Rails re-reads and re-renders database.yml on every call, so this sees the
  # worker's TEST_ENV_NUMBER.
  def refresh(current)
    rendered = ::Rails.application.config.database_configuration
    fresh = lookup(::ActiveRecord::DatabaseConfigurations.new(rendered), current)
    switch_to(rendered, fresh) unless fresh.nil? || same_hash?(fresh, current)
  end

  def reconnectable?
    defined?(::ActiveRecord::Base) &&
      defined?(::Rails) && ::Rails.respond_to?(:application) &&
      base.respond_to?(:connection_db_config)
  end

  def base
    ::ActiveRecord::Base
  end

  def switch_to(rendered, fresh)
    base.configurations = rendered
    base.establish_connection(fresh)
  end

  def same_config?(configurations, db_config)
    resolved = lookup(configurations, db_config)
    !resolved.nil? && same_hash?(resolved, db_config)
  end

  def same_hash?(one, other)
    one.configuration_hash == other.configuration_hash
  end

  def lookup(configurations, db_config)
    configurations.configs_for(env_name: db_config.env_name, name: db_config.name)
  end
end
