# frozen_string_literal: true

require "mcp"

require_relative "../mcp"

# MCP protocol revision 2026-07-28 (SEP-2322) makes `resultType` mandatory on list results: a
# client may only treat a missing field as "complete" for servers that negotiated an earlier
# revision. The mcp gem echoes back any client-offered revision it supports — 2026-07-28
# included — yet its list handlers still omit the field, so strict clients reject the whole
# list and the server appears to expose no tools at all.
#
# Every list result this server produces is final (there is no `input_required` round trip in
# the evilution tool surface), so the field is always `"complete"`. The value is written as a
# literal rather than `MCP::ResultType::COMPLETE` because the gem dependency allows versions
# that predate that constant. Older revisions ignore the extra key.
class Evilution::MCP::CompleteResultServer < MCP::Server
  RESULT_TYPE_COMPLETE = "complete"

  private

  def list_tools(request)
    mark_complete(super)
  end

  def list_prompts(request)
    mark_complete(super)
  end

  def list_resources(request)
    mark_complete(super)
  end

  def list_resource_templates(request)
    mark_complete(super)
  end

  def mark_complete(result)
    result.merge(resultType: RESULT_TYPE_COMPLETE)
  end
end
