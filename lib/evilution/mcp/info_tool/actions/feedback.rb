# frozen_string_literal: true

require_relative "base"
require_relative "../../../version"
require_relative "../../../feedback"
require_relative "../../../feedback/messages"

class Evilution::MCP::InfoTool::Actions::Feedback < Evilution::MCP::InfoTool::Actions::Base
  def self.call(**)
    success(
      "discussion_url" => Evilution::Feedback::DISCUSSION_URL,
      "version" => Evilution::VERSION,
      "guidance_for_agent" => Evilution::Feedback::Messages.info_guidance
    )
  end
end
