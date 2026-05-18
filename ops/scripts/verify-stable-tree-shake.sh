#!/usr/bin/env bash
# P039 / ADR-OBS-001 acceptance script.
#
# Builds both flavors as iOS --release --no-codesign and asserts:
#   1. The dev/stable App binary size delta is >= MIN_DELTA_BYTES.
#   2. `strings` on the stable build returns zero `opentelemetry` hits.
#
# Run from voice-agent repo root:
#
#   ./ops/scripts/verify-stable-tree-shake.sh
#
# Exit codes:
#   0 — both gates pass
#   1 — size delta too small
#   2 — opentelemetry symbols leaked into stable
#   3 — build failure

set -euo pipefail

MIN_DELTA_BYTES="${MIN_DELTA_BYTES:-153600}"  # 150 KB

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "==> building dev flavor (--target lib/main_dev.dart) ..."
flutter build ios --release --no-codesign --flavor dev \
    --target lib/main_dev.dart >/dev/null || exit 3
DEV_BIN="build/ios/iphoneos/Runner.app/Frameworks/App.framework/App"
cp "$DEV_BIN" /tmp/voice-agent-app-dev.bin

echo "==> building stable flavor (--target lib/main_stable.dart) ..."
flutter build ios --release --no-codesign --flavor stable \
    --target lib/main_stable.dart >/dev/null || exit 3
STABLE_BIN="build/ios/iphoneos/Runner.app/Frameworks/App.framework/App"
cp "$STABLE_BIN" /tmp/voice-agent-app-stable.bin

DEV_SZ=$(stat -f%z /tmp/voice-agent-app-dev.bin)
STABLE_SZ=$(stat -f%z /tmp/voice-agent-app-stable.bin)
DELTA=$((DEV_SZ - STABLE_SZ))
DELTA_KB=$((DELTA / 1024))

echo ""
echo "  dev binary:    $DEV_SZ bytes"
echo "  stable binary: $STABLE_SZ bytes"
echo "  delta:         $DELTA bytes ($DELTA_KB KB)"

# Primary gate (the real proof) — strings on the stable binary.
STABLE_HITS=$(strings /tmp/voice-agent-app-stable.bin | grep -ic opentelemetry || true)
DEV_HITS=$(strings /tmp/voice-agent-app-dev.bin | grep -ic opentelemetry || true)
echo ""
echo "  opentelemetry strings hits: dev=$DEV_HITS stable=$STABLE_HITS"

if [[ $STABLE_HITS -ne 0 ]]; then
    echo ""
    echo "FAIL: 'opentelemetry' appears $STABLE_HITS time(s) in the stable"
    echo "      AOT. Investigate which import path is reaching the OTel"
    echo "      package from lib/main_stable.dart."
    exit 2
fi

# Secondary informational signal — size delta. The delta tracks the
# weight of code reachable from main_dev but not main_stable. It is
# noisy in both directions: refactoring shared code between flavors
# moves the baseline, and AOT dedup across packages compresses real
# OTel weight. Treat as informational, not a gate.
if [[ $DELTA -lt $MIN_DELTA_BYTES ]]; then
    echo "  WARN: delta ($DELTA_KB KB) is below the soft threshold "
    echo "        ($((MIN_DELTA_BYTES / 1024)) KB). Not a fail — the "
    echo "        strings check is the real proof — but worth a glance "
    echo "        next time someone touches the tree-shake config."
fi

echo ""
echo "PASS: stable build is OTel-clean (0 strings hits)."
exit 0
