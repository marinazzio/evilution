# frozen_string_literal: true

module Evilution::CLI::Dispatcher
  @commands = {}

  class << self
    def register(symbol, klass)
      @commands[symbol] = klass
    end

    def lookup(symbol)
      @commands.fetch(symbol) { raise KeyError, "unknown command: #{symbol.inspect}" }
    end

    def registered?(symbol)
      @commands.key?(symbol)
    end

    private

    attr_reader :commands
  end
end
