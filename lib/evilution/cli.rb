# frozen_string_literal: true

require "json"
require "optparse"
require "tempfile"
require_relative "version"
require_relative "config"
require_relative "hooks"
require_relative "hooks/registry"
require_relative "hooks/loader"
require_relative "runner"
require_relative "spec_resolver"
require_relative "git/changed_files"

class Evilution::CLI
  def initialize(argv, stdin: $stdin)
    @options = {}
    @command = :run
    @stdin = stdin
    argv = argv.dup
    argv = extract_command(argv)
    argv = preprocess_flags(argv)
    raw_args = build_option_parser.parse!(argv)
    @files, @line_ranges = parse_file_args(raw_args)
    read_stdin_files if @options.delete(:stdin) && %i[run subjects].include?(@command)
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity
    case @command
    when :version             then run_version
    when :init                then run_init
    when :mcp                 then run_mcp
    when :session_list        then run_session_list
    when :session_show        then run_session_show
    when :session_diff        then run_session_diff
    when :session_gc          then run_session_gc
    when :session_error       then run_subcommand_error(@session_error)
    when :subjects            then run_subjects
    when :tests_list          then run_tests_list
    when :tests_error         then run_subcommand_error(@tests_error)
    when :environment_show    then run_environment_show
    when :environment_error   then run_subcommand_error(@environment_error)
    when :util_mutation       then run_util_mutation
    when :util_error          then run_subcommand_error(@util_error)
    when :run                 then run_mutations
    end
  end

  private

  def run_version
    $stdout.puts(Evilution::VERSION)
    0
  end

  def expand_spec_dir(dir)
    unless File.directory?(dir)
      warn("Error: #{dir} is not a directory")
      return
    end

    specs = Dir.glob(File.join(dir, "**/*_spec.rb"))
    @options[:spec_files] = Array(@options[:spec_files]) + specs
  end

  def run_subcommand_error(message)
    warn("Error: #{message}")
    2
  end

  def extract_command(argv)
    case argv.first
    when "version"
      @command = :version
      argv.shift
    when "init"
      @command = :init
      argv.shift
    when "mcp"
      @command = :mcp
      argv.shift
    when "session"
      argv.shift
      extract_session_subcommand(argv)
    when "subjects"
      @command = :subjects
      argv.shift
    when "tests"
      argv.shift
      extract_tests_subcommand(argv)
    when "environment"
      argv.shift
      extract_environment_subcommand(argv)
    when "util"
      argv.shift
      extract_util_subcommand(argv)
    when "run"
      argv.shift
    end
    argv
  end

  def extract_session_subcommand(argv)
    subcommand = argv.first
    case subcommand
    when "list"
      @command = :session_list
      argv.shift
    when "show"
      @command = :session_show
      argv.shift
    when "diff"
      @command = :session_diff
      argv.shift
    when "gc"
      @command = :session_gc
      argv.shift
    when nil
      @command = :session_error
      @session_error = "Missing session subcommand. Available subcommands: list, show, diff, gc"
    else
      @command = :session_error
      @session_error = "Unknown session subcommand: #{subcommand}. Available subcommands: list, show, diff, gc"
      argv.shift
    end
  end

  def extract_environment_subcommand(argv)
    subcommand = argv.first
    case subcommand
    when "show"
      @command = :environment_show
      argv.shift
    when nil
      @command = :environment_error
      @environment_error = "Missing environment subcommand. Available subcommands: show"
    else
      @command = :environment_error
      @environment_error = "Unknown environment subcommand: #{subcommand}. Available subcommands: show"
      argv.shift
    end
  end

  def extract_tests_subcommand(argv)
    subcommand = argv.first
    case subcommand
    when "list"
      @command = :tests_list
      argv.shift
    when nil
      @command = :tests_error
      @tests_error = "Missing tests subcommand. Available subcommands: list"
    else
      @command = :tests_error
      @tests_error = "Unknown tests subcommand: #{subcommand}. Available subcommands: list"
      argv.shift
    end
  end

  def extract_util_subcommand(argv)
    subcommand = argv.first
    case subcommand
    when "mutation"
      @command = :util_mutation
      argv.shift
    when nil
      @command = :util_error
      @util_error = "Missing util subcommand. Available subcommands: mutation"
    else
      @command = :util_error
      @util_error = "Unknown util subcommand: #{subcommand}. Available subcommands: mutation"
      argv.shift
    end
  end

  def preprocess_flags(argv)
    result = []
    i = 0
    while i < argv.length
      arg = argv[i]
      if arg == "--fail-fast"
        next_arg = argv[i + 1]

        if next_arg && next_arg.match?(/\A-?\d+\z/)
          @options[:fail_fast] = next_arg
          i += 2
        else
          result << arg
          i += 1
        end
      elsif arg.start_with?("--fail-fast=")
        @options[:fail_fast] = arg.delete_prefix("--fail-fast=")
        i += 1
      else
        result << arg
        i += 1
      end
    end
    result
  end

  def build_option_parser
    OptionParser.new do |opts|
      opts.banner = "Usage: evilution [command] [options] [files...]"
      opts.version = Evilution::VERSION
      add_separators(opts)
      add_options(opts)
    end
  end

  def add_separators(opts)
    opts.separator ""
    opts.separator "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-"
    opts.separator ""
    opts.separator "Commands: run (default), init, session {list,show,diff,gc}, subjects, tests {list},"
    opts.separator "         util {mutation}, environment {show}, mcp, version"
    opts.separator ""
    opts.separator "Options:"
  end

  def add_options(opts)
    add_core_options(opts)
    add_filter_options(opts)
    add_flag_options(opts)
    add_session_options(opts)
  end

  def add_core_options(opts)
    opts.on("-j", "--jobs N", Integer, "Number of parallel workers (default: 1)") { |n| @options[:jobs] = n }
    opts.on("-t", "--timeout N", Integer, "Per-mutation timeout in seconds") { |n| @options[:timeout] = n }
    opts.on("-f", "--format FORMAT", "Output format: text, json, html") { |f| @options[:format] = f.to_sym }
  end

  def add_filter_options(opts)
    opts.on("--min-score FLOAT", Float, "Minimum mutation score to pass") { |s| @options[:min_score] = s }
    opts.on("--spec FILES", Array, "Spec files to run (comma-separated)") { |f| @options[:spec_files] = f }
    opts.on("--spec-dir DIR", "Include all specs in DIR") { |d| expand_spec_dir(d) }
    opts.on("--target EXPR",
            "Filter: method (Foo#bar), type (Foo#/Foo.), namespace (Foo*),",
            "class (Foo), glob (source:**/*.rb), hierarchy (descendants:Foo)") do |m|
      @options[:target] = m
    end
  end

  def add_flag_options(opts)
    opts.on("--fail-fast", "Stop after N surviving mutants " \
                           "(default: disabled; if provided without N, uses 1; use --fail-fast=N)") { @options[:fail_fast] ||= 1 }
    opts.on("--no-baseline", "Skip baseline test suite check") { @options[:baseline] = false }
    opts.on("--incremental", "Cache killed/timeout results; skip re-running them on unchanged files") { @options[:incremental] = true }
    opts.on("--integration NAME", "Test integration: rspec, minitest (default: rspec)") { |i| @options[:integration] = i }
    opts.on("--isolation STRATEGY", "Isolation: auto, fork, in_process (default: auto)") { |s| @options[:isolation] = s }
    opts.on("--preload FILE", "Preload FILE in the parent process before forking " \
                              "(default: auto-detect spec/rails_helper.rb for Rails projects)") { |f| @options[:preload] = f }
    opts.on("--no-preload", "Disable parent-process preload even for Rails projects") { @options[:preload] = false }
    opts.on("--stdin", "Read target file paths from stdin (one per line)") { @options[:stdin] = true }
    opts.on("--suggest-tests", "Generate concrete test code in suggestions (RSpec or Minitest)") { @options[:suggest_tests] = true }
    opts.on("--no-progress", "Disable progress bar") { @options[:progress] = false }
    add_extra_flag_options(opts)
  end

  def add_extra_flag_options(opts)
    opts.on("--skip-heredoc-literals", "Skip all string literal mutations inside heredocs") { @options[:skip_heredoc_literals] = true }
    opts.on("--show-disabled", "Report mutations skipped by # evilution:disable") { @options[:show_disabled] = true }
    opts.on("--baseline-session PATH", "Compare against a baseline session in HTML report") { |p| @options[:baseline_session] = p }
    opts.on("--save-session", "Save session results to .evilution/results/") { @options[:save_session] = true }
    opts.on("-e", "--eval CODE", "Evaluate code snippet (for util mutation)") { |c| @options[:eval] = c }
    opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
    opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
  end

  def add_session_options(opts)
    opts.on("--results-dir DIR", "Session results directory") { |d| @options[:results_dir] = d }
    opts.on("--limit N", Integer, "Show only the N most recent sessions") { |n| @options[:limit] = n }
    opts.on("--since DATE", "Show sessions since DATE (YYYY-MM-DD)") { |d| @options[:since] = d }
    opts.on("--older-than DURATION", "Delete sessions older than DURATION (e.g., 30d, 24h, 1w)") do |d|
      @options[:older_than] = d
    end
  end

  def run_init
    path = ".evilution.yml"
    if File.exist?(path)
      warn("#{path} already exists")
      return 1
    end

    File.write(path, Evilution::Config.default_template)
    $stdout.puts("Created #{path}")
    0
  end

  def run_subjects
    raise Evilution::ConfigError, @stdin_error if @stdin_error

    config = Evilution::Config.new(target_files: @files, line_ranges: @line_ranges, **@options)
    runner = Evilution::Runner.new(config: config)
    subjects = runner.parse_and_filter_subjects

    if subjects.empty?
      $stdout.puts("No subjects found")
      return 0
    end

    registry = Evilution::Mutator::Registry.default
    filter = build_subject_filter(config)
    operator_options = build_operator_options(config)
    total_mutations = 0

    subjects.each do |subj|
      count = registry.mutations_for(subj, filter: filter, operator_options: operator_options).length
      total_mutations += count
      label = count == 1 ? "1 mutation" : "#{count} mutations"
      $stdout.puts("  #{subj.name}  #{subj.file_path}:#{subj.line_number}  (#{label})")
    ensure
      subj.release_node!
    end

    $stdout.puts("")
    $stdout.puts("#{subjects.length} subjects, #{total_mutations} mutations")
    0
  rescue Evilution::Error => e
    warn("Error: #{e.message}")
    2
  end

  def build_operator_options(config)
    { skip_heredoc_literals: config.skip_heredoc_literals? }
  end

  def build_subject_filter(config)
    return nil if config.ignore_patterns.empty?

    require_relative "ast/pattern/filter"
    Evilution::AST::Pattern::Filter.new(config.ignore_patterns)
  end

  def run_tests_list
    config = Evilution::Config.new(target_files: @files, line_ranges: @line_ranges, **@options)

    if config.spec_files.any?
      print_explicit_spec_files(config.spec_files)
      return 0
    end

    source_files = resolve_source_files(config)
    if source_files.empty?
      $stdout.puts("No source files found")
      return 0
    end

    resolver = Evilution::SpecResolver.new
    print_resolved_specs(source_files, resolver)
    0
  rescue Evilution::Error => e
    warn("Error: #{e.message}")
    2
  end

  def resolve_source_files(config)
    return config.target_files unless config.target_files.empty?

    Evilution::Git::ChangedFiles.new.call
  rescue Evilution::Error
    []
  end

  def print_explicit_spec_files(spec_files)
    spec_files.each { |f| $stdout.puts("  #{f}") }
    label = spec_files.length == 1 ? "1 spec file" : "#{spec_files.length} spec files"
    $stdout.puts("")
    $stdout.puts(label)
  end

  def print_resolved_specs(source_files, resolver)
    unique_specs = []
    source_files.each do |source|
      spec = resolver.call(source)
      if spec
        unique_specs << spec
        $stdout.puts("  #{spec}  (#{source})")
      else
        $stdout.puts("  #{source}  (no spec found)")
      end
    end

    unique_specs.uniq!
    $stdout.puts("")
    spec_label = unique_specs.length == 1 ? "1 spec file" : "#{unique_specs.length} spec files"
    $stdout.puts("#{source_files.length} source files, #{spec_label}")
  end

  def run_environment_show
    config = Evilution::Config.new(**@options)
    $stdout.puts(format_environment(config))
    0
  rescue Evilution::ConfigError => e
    warn("Error: #{e.message}")
    2
  end

  def format_environment(config)
    config_file = Evilution::Config::CONFIG_FILES.find { |path| File.exist?(path) }
    lines = environment_header(config_file)
    lines.concat(environment_settings(config))
    lines.join("\n")
  end

  def environment_header(config_file)
    [
      "Evilution Environment",
      ("=" * 30),
      "",
      "evilution: #{Evilution::VERSION}",
      "ruby: #{RUBY_VERSION}",
      "config_file: #{config_file || "(none)"}",
      "",
      "Settings:"
    ]
  end

  def environment_settings(config)
    [
      "  timeout: #{config.timeout}",
      "  format: #{config.format}",
      "  integration: #{config.integration}",
      "  jobs: #{config.jobs}",
      "  isolation: #{config.isolation}",
      "  baseline: #{config.baseline}",
      "  incremental: #{config.incremental}",
      "  verbose: #{config.verbose}",
      "  quiet: #{config.quiet}",
      "  progress: #{config.progress}",
      "  fail_fast: #{config.fail_fast || "(disabled)"}",
      "  min_score: #{config.min_score}",
      "  suggest_tests: #{config.suggest_tests}",
      "  save_session: #{config.save_session}",
      "  target: #{config.target || "(all files)"}",
      "  skip_heredoc_literals: #{config.skip_heredoc_literals}",
      "  ignore_patterns: #{config.ignore_patterns.empty? ? "(none)" : config.ignore_patterns.inspect}"
    ]
  end

  def run_mcp
    require_relative "mcp/server"
    server = Evilution::MCP::Server.build
    transport = ::MCP::Server::Transports::StdioTransport.new(server)
    transport.open
    0
  end

  def read_stdin_files
    @stdin_error = "--stdin cannot be combined with positional file arguments" unless @files.empty?
    return if @stdin_error

    lines = []
    @stdin.each_line do |line|
      line = line.strip
      lines << line unless line.empty?
    end
    stdin_files, stdin_ranges = parse_file_args(lines)
    @files = stdin_files
    @line_ranges = @line_ranges.merge(stdin_ranges)
  end

  def parse_file_args(raw_args)
    files = []
    ranges = {}

    raw_args.each do |arg|
      file, range_str = arg.split(":", 2)
      files << file
      next unless range_str

      ranges[file] = parse_line_range(range_str)
    end

    [files, ranges]
  end

  def parse_line_range(str)
    if str.include?("-")
      start_str, end_str = str.split("-", 2)
      start_line = Integer(start_str)
      end_line = end_str.empty? ? Float::INFINITY : Integer(end_str)
      start_line..end_line
    else
      line = Integer(str)
      line..line
    end
  end

  def run_util_mutation
    source, file_path = resolve_util_mutation_source
    subjects = parse_source_to_subjects(source, file_path)
    config = Evilution::Config.new(**@options)
    registry = Evilution::Mutator::Registry.default
    operator_options = build_operator_options(config)
    mutations = subjects.flat_map { |s| registry.mutations_for(s, operator_options: operator_options) }

    if mutations.empty?
      $stdout.puts("No mutations generated")
      return 0
    end

    if @options[:format] == :json
      print_util_mutations_json(mutations)
    else
      print_util_mutations_text(mutations)
    end

    0
  rescue Evilution::Error => e
    warn("Error: #{e.message}")
    2
  ensure
    @util_tmpfile&.close!
  end

  def resolve_util_mutation_source
    if @options[:eval]
      tmpfile = Tempfile.new(["evilution_eval", ".rb"])
      tmpfile.write(@options[:eval])
      tmpfile.flush
      @util_tmpfile = tmpfile
      [@options[:eval], tmpfile.path]
    elsif @files.first
      path = @files.first
      raise Evilution::Error, "file not found: #{path}" unless File.exist?(path)

      begin
        [File.read(path), path]
      rescue SystemCallError => e
        raise Evilution::Error, e.message
      end
    else
      raise Evilution::Error, "source required: use -e 'code' or provide a file path"
    end
  end

  def parse_source_to_subjects(source, file_label)
    result = Prism.parse(source)
    raise Evilution::Error, "failed to parse source: #{result.errors.map(&:message).join(", ")}" if result.failure?

    finder = Evilution::AST::SubjectFinder.new(source, file_label)
    finder.visit(result.value)
    finder.subjects
  end

  def print_util_mutations_text(mutations)
    mutations.each_with_index do |m, i|
      $stdout.puts("#{i + 1}. #{m.operator_name} — #{m.subject.name} (line #{m.line})")
      m.diff.each_line { |line| $stdout.puts("   #{line}") }
      $stdout.puts("")
    end
    label = mutations.length == 1 ? "1 mutation" : "#{mutations.length} mutations"
    $stdout.puts(label)
  end

  def print_util_mutations_json(mutations)
    data = mutations.map do |m|
      { operator: m.operator_name, subject: m.subject.name,
        file: m.file_path, line: m.line, diff: m.diff }
    end
    $stdout.puts(JSON.pretty_generate(data))
  end

  def run_session_list
    require_relative "session/store"

    store_opts = {}
    store_opts[:results_dir] = @options[:results_dir] if @options[:results_dir]
    store = Evilution::Session::Store.new(**store_opts)
    sessions = store.list
    sessions = filter_sessions(sessions)

    if sessions.empty?
      $stdout.puts("No sessions found")
      return 0
    end

    if @options[:format] == :json
      $stdout.puts(JSON.pretty_generate(sessions.map { |s| session_to_hash(s) }))
    else
      print_session_table(sessions)
    end

    0
  rescue Evilution::ConfigError => e
    warn("Error: #{e.message}")
    2
  end

  def filter_sessions(sessions)
    if @options[:since]
      cutoff = parse_date(@options[:since])
      sessions = sessions.select do |s|
        ts = s[:timestamp]
        next false unless ts.is_a?(String)

        Time.parse(ts) >= cutoff
      rescue ArgumentError
        false
      end
    end
    sessions = sessions.first(@options[:limit]) if @options[:limit]
    sessions
  end

  def parse_date(value)
    Time.parse(value)
  rescue ArgumentError
    raise Evilution::ConfigError, "invalid --since date: #{value.inspect}. Use YYYY-MM-DD format"
  end

  def run_session_show
    require_relative "session/store"

    path = @files.first
    raise Evilution::ConfigError, "session file path required" unless path

    store = Evilution::Session::Store.new
    data = store.load(path)

    if @options[:format] == :json
      $stdout.puts(JSON.pretty_generate(data))
    else
      print_session_detail(data)
    end

    0
  rescue Evilution::Error => e
    warn("Error: #{e.message}")
    2
  rescue ::JSON::ParserError => e
    warn("Error: invalid session file: #{e.message}")
    2
  end

  def run_session_diff
    require_relative "session/store"
    require_relative "session/diff"

    raise Evilution::ConfigError, "two session file paths required" unless @files.length == 2

    store = Evilution::Session::Store.new
    base_data = store.load(@files[0])
    head_data = store.load(@files[1])

    diff = Evilution::Session::Diff.new
    result = diff.call(base_data, head_data)

    if @options[:format] == :json
      $stdout.puts(JSON.pretty_generate(result.to_h))
    else
      print_session_diff(result)
    end

    0
  rescue Evilution::Error, SystemCallError => e
    warn("Error: #{e.message}")
    2
  rescue ::JSON::ParserError => e
    warn("Error: invalid session file: #{e.message}")
    2
  end

  def print_session_diff(result)
    print_diff_summary(result.summary)
    print_diff_section("Fixed (survived \u2192 killed)", result.fixed, "\e[32m")
    print_diff_section("New survivors (killed \u2192 survived)", result.new_survivors, "\e[31m")
    print_diff_section("Persistent survivors", result.persistent, "\e[33m")

    return unless result.fixed.empty? && result.new_survivors.empty? && result.persistent.empty?

    $stdout.puts("")
    $stdout.puts("No mutation changes between sessions")
  end

  def print_diff_summary(summary)
    delta_str = format("%+.2f%%", summary.score_delta * 100)
    $stdout.puts("Session Diff")
    $stdout.puts("=" * 40)
    $stdout.puts(format("Base score:  %<score>6.2f%%  (%<killed>d/%<total>d killed)",
                        score: summary.base_score * 100, killed: summary.base_killed,
                        total: summary.base_total))
    $stdout.puts(format("Head score:  %<score>6.2f%%  (%<killed>d/%<total>d killed)",
                        score: summary.head_score * 100, killed: summary.head_killed,
                        total: summary.head_total))
    $stdout.puts("Delta:       #{delta_str}")
  end

  def print_diff_section(title, mutations, color)
    return if mutations.empty?

    reset = "\e[0m"
    $stdout.puts("")
    $stdout.puts("#{color}#{title} (#{mutations.length}):#{reset}")
    mutations.each do |m|
      $stdout.puts("  #{m["operator"]} — #{m["file"]}:#{m["line"]}  #{m["subject"]}")
    end
  end

  def run_session_gc
    require_relative "session/store"

    raise Evilution::ConfigError, "--older-than is required for session gc" unless @options[:older_than]

    cutoff = parse_duration(@options[:older_than])
    store_opts = {}
    store_opts[:results_dir] = @options[:results_dir] if @options[:results_dir]
    store = Evilution::Session::Store.new(**store_opts)
    deleted = store.gc(older_than: cutoff)

    if deleted.empty?
      $stdout.puts("No sessions to delete")
    else
      $stdout.puts("Deleted #{deleted.length} session#{"s" unless deleted.length == 1}")
    end

    0
  rescue Evilution::ConfigError => e
    warn("Error: #{e.message}")
    2
  end

  def parse_duration(value)
    match = value.match(/\A(\d+)([dhw])\z/)
    raise Evilution::ConfigError, "invalid --older-than format: #{value.inspect}. Use Nd, Nh, or Nw (e.g., 30d)" unless match

    amount = match[1].to_i
    seconds = case match[2]
              when "h" then amount * 3600
              when "d" then amount * 86_400
              when "w" then amount * 604_800
              end
    Time.now - seconds
  end

  def print_session_detail(data)
    print_session_header(data)
    print_session_summary(data["summary"])
    print_survived_section(data["survived"] || [])
  end

  def print_session_header(data)
    $stdout.puts("Session: #{data["timestamp"]}")
    $stdout.puts("Version: #{data["version"]}")
    print_git_context(data["git"])
  end

  def print_git_context(git)
    return unless git.is_a?(Hash)

    branch = git["branch"]
    sha = git["sha"]
    return if branch.to_s.empty? && sha.to_s.empty?

    $stdout.puts("Git:     #{branch} (#{sha})")
  end

  def print_session_summary(summary)
    $stdout.puts("")
    $stdout.puts(
      format(
        "Score: %<score>.2f%%  Total: %<total>d  Killed: %<killed>d  Survived: %<surv>d  " \
        "Timed out: %<to>d  Errors: %<err>d  Duration: %<dur>.1fs",
        score: summary["score"] * 100, total: summary["total"], killed: summary["killed"],
        surv: summary["survived"], to: summary["timed_out"], err: summary["errors"],
        dur: summary["duration"]
      )
    )
  end

  def print_survived_section(survived)
    $stdout.puts("")
    if survived.empty?
      $stdout.puts("No survived mutations")
    else
      $stdout.puts("Survived mutations (#{survived.length}):")
      survived.each_with_index { |m, i| print_mutation_detail(m, i + 1) }
    end
  end

  def print_mutation_detail(mutation, index)
    $stdout.puts("")
    $stdout.puts("  #{index}. #{mutation["operator"]} — #{mutation["file"]}:#{mutation["line"]}")
    $stdout.puts("     Subject: #{mutation["subject"]}")
    return unless mutation["diff"]

    $stdout.puts("     Diff:")
    mutation["diff"].each_line { |line| $stdout.puts("       #{line}") }
  end

  def session_to_hash(session)
    {
      "timestamp" => session[:timestamp],
      "total" => session[:total],
      "killed" => session[:killed],
      "survived" => session[:survived],
      "score" => session[:score],
      "duration" => session[:duration],
      "file" => session[:file]
    }
  end

  def print_session_table(sessions)
    header = "Timestamp                       Total Killed  Surv.    Score Duration"
    $stdout.puts(header)
    $stdout.puts("-" * header.length)
    sessions.each { |s| print_session_row(s) }
  end

  def print_session_row(session)
    $stdout.puts(
      format(
        "%-30<ts>s %6<total>d %6<killed>d %6<surv>d %7.2<score>f%% %7.1<dur>fs",
        ts: session[:timestamp], total: session[:total], killed: session[:killed],
        surv: session[:survived], score: session[:score] * 100, dur: session[:duration]
      )
    )
  end

  def run_mutations
    raise Evilution::ConfigError, @stdin_error if @stdin_error

    file_options = Evilution::Config.file_options
    config = Evilution::Config.new(**@options, target_files: @files, line_ranges: @line_ranges)
    hooks = build_hooks(config)
    runner = Evilution::Runner.new(config: config, hooks: hooks)
    summary = runner.call
    summary.success?(min_score: config.min_score) ? 0 : 1
  rescue Evilution::Error => e
    if json_format?(config, file_options)
      $stdout.puts(JSON.generate(error_payload(e)))
    else
      warn("Error: #{e.message}")
    end
    2
  end

  def build_hooks(config)
    return nil if config.hooks.empty?

    registry = Evilution::Hooks::Registry.new
    Evilution::Hooks::Loader.call(registry, config.hooks)
    registry
  end

  def json_format?(config, file_options)
    return config.json? if config

    format = @options[:format] || (file_options && file_options[:format])
    format && format.to_sym == :json
  end

  def error_payload(error)
    error_type = case error
                 when Evilution::ConfigError then "config_error"
                 when Evilution::ParseError then "parse_error"
                 else "runtime_error"
                 end

    payload = { type: error_type, message: error.message }
    payload[:file] = error.file if error.file
    { error: payload }
  end
end
