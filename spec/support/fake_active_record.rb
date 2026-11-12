# frozen_string_literal: true

# A stand-in for the slice of ActiveRecord and Rails that per-worker database
# reconnection touches, so the behaviour can be specified without depending on
# Rails. Install with FakeActiveRecord.install(self) from inside an example;
# the constants are stubbed for that example only and survive a fork.
module FakeActiveRecord
  DbConfig = Struct.new(:env_name, :name, :configuration_hash, keyword_init: true)

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

  # Mirrors ActiveRecord::Base: configurations are fixed at boot, and the
  # connection keeps the db config it was established with.
  class Base
    class << self
      attr_reader :configurations, :connection_db_config
      attr_accessor :establish_calls

      def configurations=(raw)
        @configurations = Configurations.new(raw)
      end

      def establish_connection(db_config)
        self.establish_calls = (establish_calls || 0) + 1
        @connection_db_config = db_config
      end

      def boot(raw, env_name: "test")
        self.configurations = raw
        @connection_db_config = configurations.configs_for(env_name: env_name, name: "primary")
        self.establish_calls = 0
      end

      def use_custom_connection(hash, env_name: "test")
        @connection_db_config = DbConfig.new(env_name: env_name, name: "primary", configuration_hash: hash)
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
