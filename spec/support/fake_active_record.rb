# frozen_string_literal: true

# A stand-in for the slice of ActiveRecord and Rails that per-worker database
# reconnection touches, so the behaviour can be specified without depending on
# Rails. Install with FakeActiveRecord.install(self) from inside an example;
# the constants are stubbed for that example only and survive a fork.
module FakeActiveRecord
  DbConfig = Struct.new(:env_name, :name, :configuration_hash, keyword_init: true)

  class ConnectionNotEstablished < StandardError; end
  class NoDatabaseError < StandardError; end

  # What every database holds unless an example says otherwise: a migrated
  # schema with one table and one applied migration.
  MIGRATED = { tables: %w[schema_migrations users], versions: %w[20260101000000] }.freeze

  # Mirrors ActiveRecord::DatabaseConfigurations for a two-tier database.yml:
  # { "test" => { "adapter" => ..., "database" => ... } }.
  class Configurations
    attr_reader :raw

    def initialize(raw)
      @raw = raw
    end

    def configs_for(env_name:, name:)
      section = raw[env_name]
      return nil unless section.is_a?(Hash) && name == "primary"

      DbConfig.new(env_name: env_name, name: name, configuration_hash: section.transform_keys(&:to_sym))
    end
  end

  # A connection to one database of the registry; a database the registry
  # marks missing (nil) cannot be connected to.
  class Connection
    def initialize(schema)
      @schema = schema
    end

    def tables
      @schema.fetch(:tables)
    end

    def table_exists?(name)
      tables.include?(name)
    end

    def quote_table_name(name)
      %("#{name}")
    end

    def select_values(sql)
      raise ArgumentError, "unexpected query: #{sql}" unless sql == 'SELECT version FROM "schema_migrations"'

      @schema.fetch(:versions)
    end
  end

  class Pool
    attr_reader :db_config, :role

    def initialize(db_config, databases, role: :writing)
      @db_config = db_config
      @databases = databases
      @role = role
    end

    # A registry entry that is an exception class is raised on connect.
    def with_connection
      database = db_config.configuration_hash[:database]
      schema = @databases.fetch(database, MIGRATED)
      raise NoDatabaseError, "database #{database} does not exist" if schema.nil?
      raise schema if schema.is_a?(Class)

      yield Connection.new(schema)
    end
  end

  # Mirrors ActiveRecord::ConnectionAdapters::ConnectionHandler#connection_pool_list:
  # Base's pool plus any other pools the app set up; :all lists every role,
  # anything else the writing role only. Before Rails 7.1 :all is
  # not a role: 7.0 fails with NoMethodError, 6.1 takes no argument at all.
  # Set legacy_pool_list to the error class to model either.
  class Handler
    def initialize(base)
      @base = base
    end

    def connection_pool_list(role = nil)
      raise @base.legacy_pool_list, "no :all role" if role == :all && @base.legacy_pool_list

      pools = [@base.connection_pool] + @base.other_pools
      role == :all ? pools : pools.select { |pool| pool.role == :writing }
    end
  end

  # Mirrors ActiveRecord::Base: configurations are fixed at boot, and the
  # connection keeps the db config it was established with.
  class Base
    class << self
      attr_reader :configurations
      attr_accessor :establish_calls, :legacy_pool_list

      def configurations=(raw)
        @configurations = raw.is_a?(Configurations) ? raw : Configurations.new(raw)
      end

      def connection_db_config
        raise ::ActiveRecord::ConnectionNotEstablished, "No database connection defined." if @connection_db_config.nil?

        @connection_db_config
      end

      def establish_connection(db_config)
        self.establish_calls = (establish_calls || 0) + 1
        @connection_db_config = db_config
      end

      # One pool per established connection, as ActiveRecord hands out.
      def connection_pool
        config = connection_db_config
        @pool = Pool.new(config, databases) unless @pool && @pool.db_config.equal?(config)
        @pool
      end

      def connection_handler
        Handler.new(self)
      end

      def schema_migrations_table_name
        "schema_migrations"
      end

      # database path => { tables:, versions: }, or nil for a database that
      # does not exist. Unlisted databases are MIGRATED.
      def databases
        @databases ||= {}
      end

      def other_pools
        @other_pools ||= []
      end

      def add_pool(name, database, role: :writing)
        hash = database.nil? ? { adapter: "sqlite3" } : { adapter: "sqlite3", database: database }
        config = DbConfig.new(env_name: "test", name: name, configuration_hash: hash)
        other_pools << Pool.new(config, databases, role: role)
      end

      # A second pool built from Base's own db config, as ApplicationRecord
      # gets from connects_to without primary_abstract_class.
      def add_pool_sharing_config
        other_pools << Pool.new(connection_db_config, databases)
      end

      def boot(raw, env_name: "test")
        self.configurations = raw
        @connection_db_config = configurations.configs_for(env_name: env_name, name: "primary")
        self.establish_calls = 0
      end

      def use_custom_connection(hash, env_name: "test")
        @connection_db_config = DbConfig.new(env_name: env_name, name: "primary", configuration_hash: hash)
      end

      def remove_connection
        @connection_db_config = nil
      end
    end
  end

  # Renders database.yml the way Rails does on every call to
  # config.database_configuration: re-evaluating ERB against the current ENV.
  class AppConfig
    def initialize(&renderer)
      @renderer = renderer
    end

    def database_configuration
      @renderer.call
    end
  end

  Application = Struct.new(:config)

  def self.install(example, &renderer)
    renderer ||= -> { sqlite_yml }
    base = Class.new(Base)
    example.stub_const("ActiveRecord::Base", base)
    example.stub_const("ActiveRecord::DatabaseConfigurations", Configurations)
    example.stub_const("ActiveRecord::ConnectionNotEstablished", ConnectionNotEstablished)
    rails = Module.new
    app = Application.new(AppConfig.new(&renderer))
    rails.define_singleton_method(:application) { app }
    example.stub_const("Rails", rails)
    base.boot(renderer.call)
    base
  end

  def self.sqlite_yml
    { "test" => { "adapter" => "sqlite3", "database" => "db/test#{ENV.fetch("TEST_ENV_NUMBER", "")}.sqlite3" } }
  end
end
