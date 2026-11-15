#!/usr/bin/env bash
# Runs the operator yield study's evilution runs over the corpus.
#
#   CORPUS_DIR=<dir> OUT_DIR=<dir> scripts/operator_yield/run_study.sh [mode...]
#
# Modes (default: "default nostop generated"), per target:
#   default    one ordinary run (stop_on_kill): verdicts, per-mutant duration
#              -> <target>-default.json
#   nostop     --no-stop-on-kill with the kill-set hook: every failing example
#              per mutant -> <target>-nostop.json, <target>-nostop.jsonl
#   generated  every mutation generated before the planner's de-duplication
#              (stops after planning) -> <target>-generated.jsonl
#   ab         the A/B wall-time measurement: the default set and the set in
#              DROP_SET (operators and op:variant, comma-separated) alternated,
#              REPEATS times -> <target>-off-<n>.json, <target>-on-<n>.json
#
# CORPUS_DIR holds the corpus checkouts of scripts/benchmark_perf.yml (dirs
# fixture, dry-monads, httparty, grape, i18n, redmine; fixture is a copy of
# spec/support/fixtures/benchmark_project), each with a Gemfile named
# $CORPUS_GEMFILE (default Gemfile.operator_yield) that adds
#   gem "evilution", path: "<this repository>"
# to the project's own Gemfile. TARGETS narrows the target list.
# Wall times are appended to $OUT_DIR/wall.log.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
: "${CORPUS_DIR:?set CORPUS_DIR}" "${OUT_DIR:?set OUT_DIR}"
GEMFILE=${CORPUS_GEMFILE:-Gemfile.operator_yield}
REPEATS=${REPEATS:-2}
MODES=${*:-default nostop generated}
mkdir -p "$OUT_DIR"

# Extra hook env and evilution flags for the next run.
XENV=()
XARGS=()

evilution() { # dir env... -- args...
  local dir=$1; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  (cd "$CORPUS_DIR/$dir" && env "${envs[@]}" "${XENV[@]}" BUNDLE_GEMFILE="$CORPUS_DIR/$dir/$GEMFILE" \
    bundle exec ruby -r"$HERE/killsets_hook.rb" "$ROOT/exe/evilution" run "$@" "${XARGS[@]}" \
    --no-progress --format json)
}

timed() { # label out-file command...
  local label=$1 out=$2; shift 2
  local s e rc
  s=$(date +%s.%N)
  "$@" > "$out" 2> "${out%.*}.err"
  rc=$?
  e=$(date +%s.%N)
  echo "$label wall=$(echo "$e - $s" | bc) exit=$rc" >> "$OUT_DIR/wall.log"
}

drop_env() { # the hook's env for DROP_SET
  local list
  list=$(tr ',' '\n' <<< "${DROP_SET:?set DROP_SET for mode ab}")
  XENV=("DROP_VARIANTS=$(grep : <<< "$list" | paste -sd,)" "DROP_OPERATORS=$(grep -v : <<< "$list" | paste -sd,)")
}

one() { # name dir env... -- args...
  local name=$1; shift
  local o=$OUT_DIR/$name
  for mode in $MODES; do
    XENV=(); XARGS=()
    case $mode in
      default)   timed "$name default" "$o-default.json" evilution "$@" ;;
      nostop)    rm -f "$o-nostop.jsonl"
                 XENV=("KILLSETS_OUT=$o-nostop.jsonl"); XARGS=(--no-stop-on-kill)
                 timed "$name nostop" "$o-nostop.json" evilution "$@" ;;
      generated) rm -f "$o-generated.jsonl"
                 XENV=("GENERATED_OUT=$o-generated.jsonl" GENERATED_ONLY=1)
                 evilution "$@" > /dev/null 2>&1 ;;
      ab)        for r in $(seq 1 "$REPEATS"); do
                   XENV=(); timed "$name off $r" "$o-off-$r.json" evilution "$@"
                   drop_env; timed "$name on $r" "$o-on-$r.json" evilution "$@"
                 done ;;
    esac
  done
}

for t in ${TARGETS:-fx-pricing fx-inventory fx-grade dm-maybe hp grape i18n redmine}; do
  case $t in
    fx-pricing)   one "$t" fixture X=1 -- lib/pricing.rb --jobs 2 ;;
    fx-inventory) one "$t" fixture X=1 -- lib/inventory.rb --jobs 2 ;;
    fx-grade)     one "$t" fixture X=1 -- lib/grade.rb --jobs 2 ;;
    dm-maybe) one "$t" dry-monads X=1 -- lib/dry/monads/maybe.rb --spec spec/unit/maybe_spec.rb \
                --integration rspec --preload spec/spec_helper.rb --jobs 2 ;;
    hp)       one "$t" httparty X=1 -- lib/httparty.rb --spec spec/httparty_spec.rb \
                --integration rspec --preload spec/spec_helper.rb --jobs 2 ;;
    grape)    one "$t" grape X=1 -- lib/grape/declared_params_handler.rb --spec spec/grape/endpoint/declared_spec.rb \
                --integration rspec --preload spec/spec_helper.rb --jobs 2 ;;
    i18n)     one "$t" i18n RUBYOPT=-Itest -- lib/i18n/backend/base.rb --spec test/i18n_test.rb \
                --integration minitest --preload test/test_helper.rb --jobs 2 ;;
    redmine)  one "$t" redmine RUBYOPT=-Itest RAILS_ENV=test -- app/models/tracker.rb --spec test/unit/tracker_test.rb \
                --integration minitest --preload test/test_helper.rb --jobs 1 ;;
  esac
done
