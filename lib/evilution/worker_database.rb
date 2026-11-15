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
# database and says how to prepare its own.
#
# A worker left on the preloaded database (database.yml names the same one for
# every worker, or the worker's own is not prepared) would share it with the
# others: their fixture loads and writes collide, and verdicts depend on which
# mutations happen to run at the same time. With copies on, such a worker
# connects instead to its own copy of the preloaded SQLite database (Copies),
# which holds the same schema and data by construction.
#
# Only ActiveRecord::Base is switched; other connections are named in a
# warning. Evilution does not depend on Rails, so every reference is guarded. A
# failure is reported and the worker carries on with the inherited connection.
class Evilution::WorkerDatabase
  autoload :Schema, File.expand_path("worker_database/schema", __dir__)
  autoload :SqliteCopy, File.expand_path("worker_database/sqlite_copy", __dir__)
  autoload :Copies, File.expand_path("worker_database/copies", __dir__)

  def self.reconnect(stream: $stderr, copies: Copies::NONE)
    new(stream: stream, copies: copies).reconnect
  end

  # Whether a Rails application with ActiveRecord is loaded in this process, so
  # forked workers inherit a connection they can switch.
  def self.app_booted?
    return false unless defined?(::ActiveRecord::Base) && defined?(::Rails) && ::Rails.respond_to?(:application)

    !::Rails.application.nil? && ::ActiveRecord::Base.respond_to?(:connection_db_config)
  end

  # Whether a worker forked now, with copies on, would end up on a database of
  # its own rather than the preloaded one: the preloaded connection is the one
  # database.yml names (reconnect leaves any other alone) and it is a SQLite
  # file a copy can be made of. Asked in the parent before the workers fork.
  def self.copies_cover?
    new(stream: $stderr, copies: Copies::NONE).copies_cover?
  end

  def initialize(stream:, copies:)
    @stream = stream
    @copies = copies
  end

  def reconnect
    current = current_config
    return if current.nil? || !same_config?(base.configurations, current)

    isolate(current) unless refresh(current)
  rescue StandardError, ScriptError => e
    report("kept the preloaded connection (#{e.class}: #{e.message})")
  end

  def copies_cover?
    current = current_config
    !current.nil? && same_config?(base.configurations, current) && SqliteCopy.copyable?(current.configuration_hash)
  rescue StandardError, ScriptError
    false
  end

  private

  def current_config
    base.connection_db_config if self.class.app_booted?
  rescue ::ActiveRecord::ConnectionNotEstablished
    nil
  end

  # Whether the worker switched to a database of its own that database.yml
  # names. Rails re-reads and re-renders database.yml on every call, so this
  # sees the worker's TEST_ENV_NUMBER.
  def refresh(current)
    rendered = ::Rails.application.config.database_configuration
    fresh = lookup(::ActiveRecord::DatabaseConfigurations.new(rendered), current)
    return false if fresh.nil? || same_hash?(fresh, current)

    switch_to(current, rendered, fresh)
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
    if problem.nil?
      report_unswitched(fresh, others)
      return true
    end

    establish(previous, current)
    report_unprepared(fresh, current, problem)
    false
  end

  # Moves the worker off the shared preloaded database onto a copy of its own.
  def isolate(current)
    return unless copyable?(current)

    others = other_databases
    copy = copy_config(current, @copies.provision(source_path(current)))
    establish(configs_with(copy), copy)
    report_unswitched(copy, others)
  rescue StandardError, ScriptError => e
    report("could not copy #{database(current)} (#{e.class}: #{e.message}); " \
           "this worker shares it with the other workers.")
  end

  def copyable?(db_config)
    @copies.enabled? && SqliteCopy.copyable?(db_config.configuration_hash)
  end

  # Where the SQLite adapter opens a relative path: under Rails.root, or the
  # working directory without one.
  def source_path(db_config)
    File.expand_path(db_config.configuration_hash[:database], ::Rails.respond_to?(:root) ? ::Rails.root : nil)
  end

  def copy_config(db_config, path)
    ::ActiveRecord::DatabaseConfigurations::HashConfig.new(
      db_config.env_name, db_config.name, db_config.configuration_hash.merge(database: path)
    )
  end

  # The boot-time db configs with the copied one in place, so code that
  # reconnects by environment name (establish_connection(:test)) stays on it.
  # ActiveRecord::Base.configurations= takes a list of db configs.
  def configs_with(copy)
    base.configurations.configurations.map do |db_config|
      db_config.env_name == copy.env_name && db_config.name == copy.name ? copy : db_config
    end
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
    uses = copyable?(current) ? "a copy of the preloaded" : "the preloaded"
    report("#{database(fresh)} is not ready (#{problem}); this worker uses #{uses} " \
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
