#!/usr/bin/env bash
# End-to-end check against the LIVE shell. Disruptive: installs two fixture
# plugins that burn CPU, runs a full audit through the real Service (IPC),
# and blinks every audited plugin off and on. Afterwards it removes the
# fixtures and verifies shell.json is back to exactly what it was.
#
# Pass criteria:
#   1. both fixtures are flagged, and rank above every real plugin
#   2. the helper fixture's cost is attributed to it as helper CPU
#   3. shell.json after the audit == shell.json before it (bar placement and
#      widget settings intact -- v0.1 lost both)
#   4. no journal left behind
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
plugins="$HOME/.config/omarchy/plugins"
config="$HOME/.config/omarchy/shell.json"
state="${XDG_STATE_HOME:-$HOME/.local/state}/plugin-tax"
work="$(mktemp -d)"
fixtures=(plugintax-test.burn-child plugintax-test.burn-qml)
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
ipc() { omarchy-shell renardoberou.plugin-tax "$@"; }

cp "$config" "$work/original.json"

teardown() {
  for id in "${fixtures[@]}"; do
    omarchy plugin disable "$id" >/dev/null 2>&1
    rm -f "$plugins/$id"
  done
  omarchy-shell -q shell rescanPlugins >/dev/null 2>&1
  sleep 1
  check "shell.json back to the pre-test original" \
    "[[ \"\$(jq -S . \"$work/original.json\")\" == \"\$(jq -S . \"$config\")\" ]]"
  rm -rf "$work"
  exit $fail
}
trap teardown EXIT

# Fixture manifests are stored as fixture-manifest.json so the marketplace
# validator never mistakes them for extra plugins in this repository; build
# real plugin folders from them in a temp dir.
for name in burn-child burn-qml; do
  mkdir -p "$work/$name"
  cp -r "$here/fixtures/$name/." "$work/$name/"
  mv "$work/$name/fixture-manifest.json" "$work/$name/manifest.json"
  ln -sfn "$work/$name" "$plugins/plugintax-test.$name"
done
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1
# The rescan is asynchronous; wait until the shell knows both fixtures.
for (( i = 0; i < 40; i++ )); do
  omarchy plugin list --json | jq -e --argjson want "$(printf '%s\n' "${fixtures[@]}" | jq -R . | jq -s .)" \
    '[.[].id] as $have | all($want[]; . as $w | $have | index($w))' >/dev/null && break
  sleep 0.25
done
for id in "${fixtures[@]}"; do omarchy plugin enable "$id" >/dev/null || { echo "could not enable $id"; exit 1; }; done
sleep 3
cp "$config" "$work/before.json"

echo "# audit: $(ipc runAudit)"
for (( i = 0; i < 600; i++ )); do
  sleep 1
  st="$(ipc status)"
  [[ "$(jq -r .auditing <<<"$st")" == false ]] && (( i > 2 )) && break
  (( i % 10 == 0 )) && jq -r '"#   " + ((.progress.index // 0)|tostring) + "/" + ((.progress.total // 0)|tostring) + " " + (.progress.name // "")' <<<"$st"
done
cp "$config" "$work/after.json"

echo "$st" | jq -r '.results[] | "#   \(.verdict)\t\(.costPct|.*10|round/10)%\thelper \(.helperPct|.*10|round/10)%\tdeltas \(.deltaPct|.*10|round/10)±\(.spreadPct|.*10|round/10)\t\(.id)"'
echo "$st" | jq -r '.warnings[]? | "# warning: " + .'

check "burn-child flagged" "jq -e '.results[] | select(.id==\"plugintax-test.burn-child\") | .verdict==\"flagged\"' <<<\"\$st\" >/dev/null"
check "burn-qml flagged" "jq -e '.results[] | select(.id==\"plugintax-test.burn-qml\") | .verdict==\"flagged\"' <<<\"\$st\" >/dev/null"
check "fixtures rank first" "jq -e '[.results[:2][].id] | sort == [\"plugintax-test.burn-child\",\"plugintax-test.burn-qml\"]' <<<\"\$st\" >/dev/null"
check "helper CPU attributed to burn-child (10-20%)" "jq -e '.results[] | select(.id==\"plugintax-test.burn-child\") | .helperPct > 10 and .helperPct < 20' <<<\"\$st\" >/dev/null"
check "shell.json unchanged by the audit" "[[ \"\$(jq -S . \"$work/before.json\")\" == \"\$(jq -S . \"$work/after.json\")\" ]]"
check "no journal left" "[[ ! -e \"$state/journal.json\" ]]"
