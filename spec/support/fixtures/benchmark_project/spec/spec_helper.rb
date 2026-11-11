# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# A little per-example latency so kill checks have a cost worth measuring
# (fail-fast and example ordering only show up when examples are not free).
SLOW_EXAMPLE_SECONDS = 0.05
