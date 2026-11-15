#!/usr/bin/env bash
# Runs the tests of the modules this branch touches, for the dev loop (#423).
# The full suite (`make verify`) still runs before a PR goes ready.
#
#   scripts/test-changed.sh          # changes since the merge base with origin/main
#   BASE=<ref> scripts/test-changed.sh
#   DRY=1 scripts/test-changed.sh    # print what would run
#
# A module is the second level under lib/ or test/: lib/features/agenda/… maps
# to test/features/agenda/, lib/core/storage/… to test/core/storage/. Files
# straight under lib/ or lib/app/ map to test/app/. A changed test file runs
# with its module. pubspec.yaml beyond its version line, pubspec.lock,
# analysis_options.yaml, assets/ and test/helpers/ run the full suite: they can
# break anything. Native code (android/, ios/) has no Dart tests.

set -euo pipefail

base=${BASE:-$(git merge-base HEAD origin/main)}

mapfile -t changed < <(
    {
        git diff --name-only "$base"            # committed + uncommitted
        git ls-files --others --exclude-standard  # new files
    } | sort -u
)

declare -A dirs=()
full=""
for f in "${changed[@]}"; do
    case $f in
        lib/*.dart | lib/app/*) dirs[test/app]=1 ;;
        lib/*/*/*) m=${f#lib/}; m=${m%%/*}/$(cut -d/ -f3 <<<"$f"); dirs[test/$m]=1 ;;
        test/helpers/*) full="test/helpers changed" ;;
        test/*/*/*) dirs[$(cut -d/ -f1-3 <<<"$f")]=1 ;;
        test/*) dirs[$(dirname "$f")]=1 ;;
        pubspec.yaml)
            # A version bump alone (every feature PR has one) runs nothing.
            if git diff "$base" -- pubspec.yaml | grep -E '^[+-][^+-]' | grep -qvE '^[+-]version:'; then
                full="pubspec.yaml changed"
            fi ;;
        pubspec.lock | analysis_options.yaml | assets/*) full="$f changed" ;;
        *) ;;  # android/, ios/ (native: the device check), docs, Makefile, scripts
    esac
done

if [[ -n $full ]]; then
    echo "test-changed: $full -> full suite"
    [[ -n ${DRY:-} ]] && exit 0
    exec flutter test
fi

targets=()
for d in "${!dirs[@]}"; do
    if [[ -d $d ]] && find "$d" -name '*_test.dart' -print -quit | grep -q .; then
        targets+=("$d")
    else
        echo "test-changed: no tests under $d"
    fi
done

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "test-changed: nothing to run (base $(git rev-parse --short "$base"))"
    exit 0
fi

mapfile -t targets < <(printf '%s\n' "${targets[@]}" | sort)
echo "test-changed: ${targets[*]}"
[[ -n ${DRY:-} ]] && exit 0
exec flutter test "${targets[@]}"
