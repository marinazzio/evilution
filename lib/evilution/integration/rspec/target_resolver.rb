# frozen_string_literal: true

require_relative "../rspec"

# Targets are passed straight through when they resolve against Dir.pwd,
# preserving the relative-path contract for callers/tests. When the CWD
# cannot find them — workers chdir'd into a per-mutation sandbox by the
# isolator (EV-wqxu / GH #1278) — the targets are expanded against
# Evilution::PROJECT_ROOT so RSpec::Core::Runner can still load the files.
class Evilution::Integration::RSpec::TargetResolver
  # Splits a target into (path, line). RSpec example locations end in
  # `:LINE` (or `:LINE:LINE...` for nested groups), so the suffix is
  # anchored to the END of the string — that way path components which
  # themselves contain colons (e.g. a Windows-style `C:/proj/spec/x.rb`)
  # are not mis-split by a naive `partition(":")`.
  TARGET_LINE_SUFFIX = /\A(.+?)(:\d+(?::\d+)*)\z/
  private_constant :TARGET_LINE_SUFFIX

  def call(targets)
    targets.map { |target| resolve(target) }
  end

  def resolve(target)
    return target if target.start_with?("/")

    if (match = TARGET_LINE_SUFFIX.match(target))
      path = match[1]
      line_suffix = match[2]
    else
      path = target
      line_suffix = ""
    end

    return target if File.exist?(path)
    return target unless Evilution.in_isolated_worker?

    absolute = File.expand_path(path, Evilution::PROJECT_ROOT)
    return target unless File.exist?(absolute)

    "#{absolute}#{line_suffix}"
  end
end
