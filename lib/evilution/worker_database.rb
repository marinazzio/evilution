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
# test helper) is left alone. The worker's database must already hold the
# preloaded database's schema: an empty or missing one would fail every test
# and report every mutation killed, so the worker goes back to the preloaded
# database and says how to prepare its own. Only ActiveRecord::Base is
# switched; other connections are named in a warning. Evilution does not depend
# on Rails, so every reference is guarded. A failure is reported and the worker
# carries on with the inherited connection.
class Evilution::WorkerDatabase
  def self.reconnect(stream: $stderr)
    new(stream: stream).reconnect
  end

  def initialize(stream:)
    @stream = stream
  end

  def reconnect
    current = current_config
    refresh(current) if !current.nil? && same_config?(base.configurations, current)
  rescue StandardError, ScriptError => e
    report("kept the preloaded connection (#{e.class}: #{e.message})")
  end

  private

  def current_config
    base.connection_db_config if reconnectable?
  rescue ::ActiveRecord::ConnectionNotEstablished
    nil
  end

  # Rails re-reads and re-renders database.yml on every call, so this sees the
  # worker's TEST_ENV_NUMBER.
  def refresh(current)
    rendered = ::Rails.application.config.database_configuration
    fresh = lookup(::ActiveRecord::DatabaseConfigurations.new(rendered), current)
    switch_to(current, rendered, fresh) unless fresh.nil? || same_hash?(fresh, current)
  end

  def reconnectable?
    defined?(::ActiveRecord::Base) &&
      defined?(::Rails) && ::Rails.respond_to?(:application) && !::Rails.application.nil? &&
      base.respond_to?(:connection_db_config)
  end

  def base
    ::ActiveRecord::Base
  end

  def switch_to(current, rendered, fresh)
    reference = Schema.of(base)
    others = other_databases
    previous = base.configurations
    establish(rendered, fresh)
    problem = unprepared(reference)
    return report_unswitched(fresh, others) if problem.nil?

    establish(previous, current)
    report_unprepared(fresh, current, problem)
  end

  def establish(configurations, db_config)
    base.configurations = configurations
    base.establish_connection(db_config)
  end

  def unprepared(reference)
    Schema.of(base).missing_from(reference)
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  # Pools of other abstract classes, roles and shards keep pointing at the
  # preloaded databases. Rails before 7.1 has no :all role (7.0 fails on it,
  # 6.1 takes no argument) and lists the current role's pools only.
  def other_databases
    handler = base.connection_handler
    pools = begin
      handler.connection_pool_list(:all)
    rescue NoMethodError, ArgumentError
      handler.connection_pool_list
    end
    own = base.connection_pool
    pools.reject { |pool| pool.equal?(own) }.map { |pool| database(pool.db_config) }.uniq
  end

  def report_unswitched(fresh, others)
    return if others.empty?

    report("switched ActiveRecord::Base to #{database(fresh)}, but other connections still use " \
           "the preloaded #{others.join(", ")}. See README.")
  end

  def report_unprepared(fresh, current, problem)
    number = ENV.fetch("TEST_ENV_NUMBER", "")
    report("#{database(fresh)} is not ready (#{problem}); this worker uses the preloaded " \
           "#{database(current)}. Prepare it with `TEST_ENV_NUMBER=#{number} bin/rails db:test:prepare`.")
  end

  def report(message)
    Evilution::Diagnostic.warn("[evilution] worker database: #{message}", stream: @stream)
  end

  def database(db_config)
    db_config.configuration_hash[:database] || db_config.name
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

require_relative "worker_database/schema"
