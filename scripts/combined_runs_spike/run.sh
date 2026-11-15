#!/usr/bin/env bash
# run.sh <target> <tag> <mode> [VAR=value ...]
#
#   target  fix | fm | dm | hp | gr (fixture, constructed project, dry-monads,
#           httparty, grape), each a directory under $CORPUS (see README.md)
#   tag     run name; output goes to $OUT/<target>-<tag>.json, .stats.json, .err
#   mode    c = control (plan and stats only, single runs)
#           x = combined (EV_COMBINED=1)
#   VAR=value  extra harness settings, e.g. EV_COMBINED_CAP=4
set -u
here=$(cd "$(dirname "$0")" && pwd)
: "${CORPUS:?set CORPUS to the directory holding the target copies}"
OUT=${OUT:-$CORPUS/out}
t=$1 tag=$2 mode=$3
shift 3
gem=""
case $t in
  fix) dir=$CORPUS/fixture; args="lib/pricing.rb lib/inventory.rb lib/grade.rb --preload spec/spec_helper.rb";;
  fm) dir=$CORPUS/fm; args="lib/fm.rb --spec spec/fm_spec.rb --preload spec/spec_helper.rb";;
  dm) dir=$CORPUS/dry-monads; gem=$dir/Gemfile.spike
      args="lib/dry/monads/maybe.rb --spec spec/unit/maybe_spec.rb --integration rspec --preload spec/spec_helper.rb";;
  hp) dir=$CORPUS/httparty; gem=$dir/Gemfile.spike
      args="lib/httparty.rb --spec spec/httparty_spec.rb --integration rspec --preload spec/spec_helper.rb";;
  gr) dir=$CORPUS/grape; gem=$dir/Gemfile.spike
      args="lib/grape/declared_params_handler.rb --spec spec/grape/endpoint/declared_spec.rb --integration rspec --preload spec/spec_helper.rb";;
  *) echo "unknown target: $t" >&2; exit 2;;
esac
cd "$dir" || exit 1
[ -n "$gem" ] && export BUNDLE_GEMFILE=$gem
[ "$mode" = x ] && export EV_COMBINED=1
for kv in "$@"; do export "${kv?}"; done
mkdir -p "$OUT"
export EV_COMBINED_OUT=$OUT/$t-$tag.stats.json
start=$(date +%s.%N)
# shellcheck disable=SC2086 # args is a word list on purpose
RUBYOPT="-r$here/combined.rb ${RUBYOPT:-}" bundle exec evilution run $args --jobs 2 \
  --example-targeting coverage --isolation fork --format json > "$OUT/$t-$tag.json" 2> "$OUT/$t-$tag.err"
rc=$?
end=$(date +%s.%N)
echo "$t $tag $mode exit=$rc wall=$(echo "$end - $start" | bc)" | tee -a "$OUT/runs.log"
