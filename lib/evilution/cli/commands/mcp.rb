# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"

class Evilution::CLI::Commands::Mcp < Evilution::CLI::Command
  private

  def perform
    require_relative "../../mcp/server"
    server = Evilution::MCP::Server.build
    transport = ::MCP::Server::Transports::StdioTransport.new(server)
    transport.open
    0
  end
end

Evilution::CLI::Dispatcher.register(:mcp, Evilution::CLI::Commands::Mcp)
