# frozen_string_literal: true

require "evilution/version"
require "evilution/feedback/messages"

RSpec.describe Evilution::Feedback::Messages do
  describe ".cli_footer" do
    it "includes the discussion URL" do
      expect(described_class.cli_footer).to include(Evilution::Feedback::DISCUSSION_URL)
    end

    it "includes the current evilution version" do
      expect(described_class.cli_footer).to include(Evilution::VERSION)
    end

    it "starts with a friction nudge" do
      expect(described_class.cli_footer).to match(/friction/i)
    end
  end

  describe ".mcp_hint" do
    it "explicitly forbids posting without user permission" do
      expect(described_class.mcp_hint).to match(/do not post|never post/i)
      expect(described_class.mcp_hint).to match(/explicit.*permission|user.*approval/i)
    end

    it "names the four trigger classes" do
      hint = described_class.mcp_hint
      expect(hint).to match(/error/i)
      expect(hint).to match(/usage/i)
      expect(hint).to match(/friction/i)
      expect(hint).to match(/missing|wishlist|future/i)
    end
  end

  describe ".info_guidance" do
    it "explains the consent gate" do
      expect(described_class.info_guidance).to match(/consent|permission|approval/i)
    end

    it "covers privacy expectations" do
      guidance = described_class.info_guidance
      expect(guidance).to match(/secret|token|env/i)
      expect(guidance).to match(/path|project|file/i)
    end

    it "names the four trigger classes" do
      guidance = described_class.info_guidance
      expect(guidance).to match(/error/i)
      expect(guidance).to match(/usage/i)
      expect(guidance).to match(/friction/i)
      expect(guidance).to match(/missing|wishlist|future/i)
    end
  end
end
