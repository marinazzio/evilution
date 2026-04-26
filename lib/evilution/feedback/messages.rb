# frozen_string_literal: true

require_relative "../feedback"
require_relative "../version"

module Evilution::Feedback::Messages
  module_function

  def cli_footer
    "> Hit friction with evilution v#{Evilution::VERSION}? " \
      "Share details: #{Evilution::Feedback::DISCUSSION_URL}"
  end

  def mcp_hint
    "Feedback welcome on errors, usage problems, friction, or missing " \
      "capabilities you wish were there. Do NOT post on the user's " \
      "behalf without explicit user permission. Show the user exactly " \
      "what you would post and only submit after their explicit approval. " \
      "Never include secrets, env vars, project name, file paths, source " \
      "code, or class/method names from user code."
  end

  def info_guidance
    <<~GUIDANCE.chomp
      The maintainer welcomes feedback in four cases:
        1. Errors raised by evilution
        2. Usage problems (confusing behavior, unexpected output)
        3. Friction (slow runs, awkward workflow, hard-to-interpret output)
        4. Missing capabilities or features you wish were there

      CONSENT (required):
        Never post on the user's behalf without explicit user permission.
        Show the user exactly what you would post. Submit only after the
        user explicitly approves.

      PRIVACY (required):
        Never include secrets, tokens, environment variables, the project
        name, absolute or project-relative file paths, source code, or
        class/method names from user code. The feedback channel is public.
    GUIDANCE
  end
end
