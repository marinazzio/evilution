# frozen_string_literal: true

# Mutant-schemata spike harness, loaded with `RUBYOPT=-r<this file>`.
#
#   EV_SCHEMATA=1            build and use the meta-version (else: stats only)
#   EV_SCHEMATA_STATS=<path> write eligibility stats (JSON) from the parent
#
# Parent, after warm-up and before any mutation runs: for every file, find the
# mutations whose change lies inside the body of a statically nested `def`,
# rebuild each such method with a switch on $__evilution_schema:
#
#   case $__evilution_schema when nil then begin <original body, original lines>
#   end when 17 then begin
#   <body with mutation 17>
#   end ... else begin <original body> end end
#
# and class_eval it alone, inside the file's own nesting (`module A; class B;`
# on the def's line), so nothing else in the file is evaluated again and every
# line outside the variants keeps its number. Visibility, module_function
# copies and in-file aliases of the method are re-applied.
#
# Child: applying a switched mutation sets $__evilution_schema and returns;
# restoring it clears it. Under in_process isolation, restoring a mutation of
# the same file that took the eval path puts the meta-methods back.
require "bundler/setup"
require "json"
require "prism"
require "evilution"
require "evilution/integration/loading/mutation_applier"
require "evilution/runner/mutation_executor"

# The switch is a global on purpose: the meta-methods read it from any
# class, and the per-call cost of the switch was measured with a global.
$__evilution_schema = nil # rubocop:disable Style/GlobalVars

module SchemataSpike
  LOCAL_WRITES = [Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode,
                  Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableAndWriteNode,
                  Prism::LocalVariableOrWriteNode].freeze

  STATIC = [Prism::ProgramNode, Prism::StatementsNode, Prism::ClassNode, Prism::ModuleNode,
            Prism::SingletonClassNode].freeze

  class << self
    attr_reader :table, :metas

    def enabled? = ENV["EV_SCHEMATA"] == "1"

    def key(mutation) = [mutation.file_path, mutation.mutated_source.hash]

    def install(mutations)
      @table = {}
      @next_id = 0
      @metas = Hash.new { |h, k| h[k] = [] }
      stats = Hash.new(0)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rss_before = rss
      mutations.group_by(&:file_path).each { |file, ms| install_file(file, ms, stats) }
      stats["build_and_eval_seconds"] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      stats["rss_kb_delta"] = rss - rss_before
      stats["total"] = mutations.size
      File.write(ENV["EV_SCHEMATA_STATS"], JSON.pretty_generate(stats)) if ENV["EV_SCHEMATA_STATS"]
    end

    def rss = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i

    # Applies the file's meta-methods; run again after an in_process restore.
    def apply_metas(file)
      @metas[file].each { |meta| eval_meta(meta) }
    end

    private

    def install_file(file, mutations, stats)
      base = common_restore_source(mutations)
      tree = Prism.parse(base)
      return stats["file_unparseable"] += mutations.size if tree.failure?

      defs = static_defs(tree.value, [])
      alias_pairs = aliases(tree.value)
      by_def = Hash.new { |h, k| h[k] = [] }
      mutations.each do |m|
        reason, info = classify(m, base, defs)
        stats["ineligible:#{reason}"] += 1 if reason
        by_def[info[:def]] << [m, info] unless reason
      end
      require_target(file)
      by_def.each do |entry, list|
        variants = []
        list.each do |m, info|
          text = base.byteslice(entry[:body_start]...info[:from]) + info[:replacement] +
                 base.byteslice(info[:to]...entry[:body_end])
          if line_sensitive?(text)
            stats["ineligible:line_sensitive"] += 1
            next
          end
          variants << [(@next_id += 1), m, text]
        end
        variants = drop_local_conflicts(base, entry, variants, stats)
        next if variants.empty?

        meta = build_meta(base, file, entry, variants, alias_pairs)
        if eval_meta(meta)
          @metas[file] << meta
          variants.each { |vid, m, _| @table[key(m)] = vid }
          stats["eligible"] += variants.size
        else
          stats["ineligible:meta_eval_failed"] += variants.size
        end
      end
    end

    # The neutralized original every ordinary mutation's restore source is;
    # scope/aasm/callback/concern-hook subjects keep a declaration of their
    # own and fall outside it.
    def common_restore_source(mutations)
      mutations.map(&:restore_source).compact.tally.max_by { |_, n| n }.first
    end

    def classify(mutation, base, defs)
      return [:unparseable] if mutation.unparseable?
      return [:redeclared_subject] unless mutation.restore_source == base

      from, to, replacement = change(base, mutation.eval_source)
      return [:no_change] if from.nil?

      entry = defs.find { |d| d[:body_start] <= from && to <= d[:body_end] }
      return [:outside_static_def_body] unless entry
      return [:endless_def] if entry[:endless]

      [nil, { def: entry, from: from, to: to, replacement: replacement }]
    end

    # Common prefix and suffix of the two sources: the changed byte range of
    # base and what replaces it.
    def change(base, mutated)
      a = base.b
      b = mutated.b
      return nil if a == b

      p = 0
      max = [a.bytesize, b.bytesize].min
      p += 1 while p < max && a.getbyte(p) == b.getbyte(p)
      s = 0
      s += 1 while s < max - p && a.getbyte(a.bytesize - 1 - s) == b.getbyte(b.bytesize - 1 - s)
      [p, a.bytesize - s, b.byteslice(p...(b.bytesize - s)).force_encoding(base.encoding)]
    end

    # defs reachable through class/module/singleton-class bodies only, with
    # the openers that reproduce their nesting.
    def static_defs(node, openers, out = [])
      case node
      when Prism::DefNode
        add_def(node, openers, out)
      when Prism::ClassNode, Prism::ModuleNode
        keyword = node.is_a?(Prism::ClassNode) ? "class" : "module"
        inner = openers + ["#{keyword} #{node.constant_path.slice}"]
        static_defs(node.body, inner, out) if node.body
      when Prism::SingletonClassNode
        return out unless node.expression.is_a?(Prism::SelfNode)

        static_defs(node.body, openers + ["class << self"], out) if node.body
      when Prism::ProgramNode
        static_defs(node.statements, openers, out)
      when Prism::StatementsNode
        node.body.each { |child| static_defs(child, openers, out) }
      when Prism::CallNode
        # `private def foo` and friends
        args = node.arguments
        args&.arguments&.each { |a| static_defs(a, openers, out) if a.is_a?(Prism::DefNode) } if node.receiver.nil?
      end
      out
    end

    def add_def(node, openers, out)
      return if node.receiver && !node.receiver.is_a?(Prism::SelfNode)
      return if node.body.nil?

      endless = node.end_keyword_loc.nil?
      body = node.body
      first = body.is_a?(Prism::BeginNode) && body.begin_keyword_loc.nil? ? implicit_begin_start(body) : body.location.start_offset
      out << { node: node, openers: openers, endless: endless, body_start: first,
               body_end: endless ? body.location.end_offset : node.end_keyword_loc.start_offset }
    end

    def implicit_begin_start(body)
      [body.statements, body.rescue_clause, body.else_clause, body.ensure_clause].compact.first.location.start_offset
    end

    def aliases(root)
      pairs = []
      walk(root) do |n|
        case n
        when Prism::AliasMethodNode
          pairs << [n.new_name.slice.delete_prefix(":").to_sym, n.old_name.slice.delete_prefix(":").to_sym]
        when Prism::CallNode
          if n.name == :alias_method && n.arguments && n.arguments.arguments.size == 2
            names = n.arguments.arguments.map { |a| a.respond_to?(:unescaped) ? a.unescaped.to_sym : nil }
            pairs << names if names.all?
          end
        end
      end
      pairs
    end

    def walk(node, &blk)
      return unless node

      yield node
      node.compact_child_nodes.each { |c| walk(c, &blk) }
    end

    # Constructs whose value depends on the line the code is on, or that see
    # the method's whole local table.
    def line_sensitive?(text)
      text.include?("__LINE__") || text.match?(/\b(binding|local_variables)\b/)
    end

    # A name that is a method call in a variant (no local of that name
    # assigned before it) would read as a local in the meta-method when an
    # earlier branch assigns it. Such variants are dropped.
    def drop_local_conflicts(base, entry, variants, stats)
      header = base.byteslice(entry[:node].location.start_offset...entry[:body_start])
      declared = locals_written("#{header}#{base.byteslice(entry[:body_start]...entry[:body_end])}\nend")
      variants.reject do |_vid, _m, text|
        vcalls = variable_calls("#{header}#{text}\nend")
        conflict = vcalls.intersect?(declared)
        declared |= locals_written("#{header}#{text}\nend")
        stats["ineligible:local_conflict"] += 1 if conflict
        conflict
      end
    end

    def locals_written(src)
      names = Set.new
      walk(Prism.parse(src).value) { |n| names << n.name if LOCAL_WRITES.any? { |k| n.is_a?(k) } }
      names
    end

    def variable_calls(src)
      names = Set.new
      walk(Prism.parse(src).value) { |n| names << n.name if n.is_a?(Prism::CallNode) && n.variable_call? }
      names
    end

    def build_meta(base, file, entry, variants, alias_pairs)
      node = entry[:node]
      original = base.byteslice(entry[:body_start]...entry[:body_end])
      head = base.byteslice(node.location.start_offset...entry[:body_start])
      tail = base.byteslice(entry[:body_end]...node.location.end_offset)
      body = "case $__evilution_schema when nil then begin #{original}\nend"
      variants.each { |vid, _, text| body << " when #{vid} then begin\n#{text}\nend" }
      body << " else begin\n#{original}\nend end\n"
      openers = entry[:openers].map { |o| "#{o}; " }.join
      closers = entry[:openers].map { "\nend" }.join
      {
        file: File.expand_path(file, Evilution.project_base_dir),
        line: node.location.start_line,
        owner_src: "#{openers}#{node.receiver ? "class << self; self; end" : "self"}#{closers}",
        def_src: "#{openers}#{head}#{body}#{tail}#{closers}",
        name: node.name,
        aliases: alias_pairs.select { |_, old| old == node.name }.map(&:first)
      }
    end

    def eval_meta(meta)
      # Evaluates source built from the target file itself, under its path and line.
      owner = eval(meta[:owner_src], TOPLEVEL_BINDING, meta[:file], meta[:line]) # rubocop:disable Security/Eval
      name = meta[:name]
      vis = visibility(owner, name)
      mod_fn = module_function?(owner, name)
      alias_vis = meta[:aliases].select { |a| owner.method_defined?(a) || owner.private_method_defined?(a) }
                                .to_h { |a| [a, visibility(owner, a)] }
      Evilution::Integration::Loading::ReevalWarningFilter.suppress do
        eval(meta[:def_src], TOPLEVEL_BINDING, meta[:file], meta[:line]) # rubocop:disable Security/Eval
        owner.send(:module_function, name) if mod_fn
        owner.send(vis, name) if vis && !mod_fn
        alias_vis.each do |a, v|
          owner.send(:alias_method, a, name)
          owner.send(v, a) if v
        end
      end
      true
    rescue ScriptError, StandardError => e
      warn "[schemata] #{meta[:file]}:#{meta[:line]} #{name}: #{e.class}: #{e.message}"
      false
    end

    def visibility(owner, name)
      return :private if owner.private_method_defined?(name)
      return :protected if owner.protected_method_defined?(name)
      return :public if owner.public_method_defined?(name)

      nil
    end

    def module_function?(owner, name)
      return false if owner.is_a?(Class) || !owner.private_method_defined?(name)
      return false unless owner.singleton_class.method_defined?(name)

      owner.singleton_class.instance_method(name).source_location == owner.instance_method(name).source_location
    end

    def require_target(file)
      path = File.realpath(File.expand_path(file, Evilution.project_base_dir))
      require path unless $LOADED_FEATURES.include?(path)
    end
  end

  module ExecutorHook
    private

    def warm(integration, mutations)
      super
      SchemataSpike.install(mutations) if SchemataSpike.enabled?
      Process.warmup if ENV["EV_PARENT_WARMUP"] == "1"
    end
  end

  module ApplierHook
    def call(mutation)
      id = SchemataSpike.enabled? && SchemataSpike.table && SchemataSpike.table[SchemataSpike.key(mutation)]
      return super unless id

      $__evilution_schema = id # rubocop:disable Style/GlobalVars
      SchemataSpike.apply_metas(mutation.file_path) if ENV["EV_SCHEMATA_REEVAL"] == "1"
      GC.start if ENV["EV_SCHEMATA_GC"] == "1"
      nil
    end

    def restore(mutation)
      table = SchemataSpike.enabled? && SchemataSpike.table
      return super unless table
      return ($__evilution_schema = nil) if table[SchemataSpike.key(mutation)] # rubocop:disable Style/GlobalVars

      super
      SchemataSpike.apply_metas(mutation.file_path)
    end
  end
end

Evilution::Runner::MutationExecutor.prepend(SchemataSpike::ExecutorHook)
Evilution::Integration::Loading::MutationApplier.prepend(SchemataSpike::ApplierHook)

if ENV["EV_GCSTAT"]
  require "evilution/integration/base"
  module SchemataSpike::GcStat
    def call(mutation)
      before = GC.stat.slice(:time, :count, :major_gc_count)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super
    ensure
      after = GC.stat.slice(:time, :count, :major_gc_count)
      File.open(ENV["EV_GCSTAT"], "a") do |f|
        f.puts [after[:time] - before[:time], after[:count] - before[:count],
                after[:major_gc_count] - before[:major_gc_count],
                ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(2)].join("\t")
      end
    end
  end
  Evilution::Integration::Base.prepend(SchemataSpike::GcStat)
end

# Alternative measured alongside: the constant names of a file's original
# source, parsed once in the parent instead of once per mutation.
if ENV["EV_PIN_MEMO"] == "1"
  module SchemataSpike
    PIN_MEMO = {} # rubocop:disable Style/MutableConstant -- the memo, filled at warm-up
    module PinMemo
      def call(source)
        PIN_MEMO[source] ||= super
        PIN_MEMO[source].each do |name|
          Object.const_get(name) if Object.const_defined?(name, false)
        rescue NameError
          nil
        end
      end
    end

    module PinWarm
      private

      def warm(integration, mutations)
        super
        pinner = Evilution::Integration::Loading::ConstantPinner.new
        mutations.map(&:original_source).uniq.each { |s| pinner.call(s) }
      end
    end
  end
  Evilution::Integration::Loading::ConstantPinner.prepend(SchemataSpike::PinMemo)
  Evilution::Runner::MutationExecutor.prepend(SchemataSpike::PinWarm)
end
