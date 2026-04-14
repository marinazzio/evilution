# frozen_string_literal: true

require "mcp"
require "evilution/cli/commands/mcp"
require "evilution/cli/parsed_args"
require "evilution/mcp/server"

RSpec.describe Evilution::CLI::Commands::Mcp do
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :mcp) }

  it "builds the server, opens the transport, and returns exit code 0" do
    server = instance_double("Evilution::MCP::Server")
    transport = instance_double("MCP::Server::Transports::StdioTransport", open: nil)
    allow(Evilution::MCP::Server).to receive(:build).and_return(server)
    allow(MCP::Server::Transports::StdioTransport).to receive(:new).with(server).and_return(transport)

    result = described_class.new(parsed).call
    expect(result.exit_code).to eq(0)
    expect(transport).to have_received(:open)
  end

  it "is registered with the dispatcher under :mcp" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:mcp)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:mcp)).to eq(described_class)
  end
end
