#!/usr/bin/env bash
# Exercises plugin-tax-audit's restore paths against a mock omarchy CLI and a
# throwaway shell.json -- never touches the real shell or config.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
audit="$here/../bin/plugin-tax-audit"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PATH="$here/mock:$PATH" PLUGIN_TAX_CONFIG="$tmp/shell.json" PLUGIN_TAX_STATE="$tmp/state" MOCK_IDS="$tmp/ids.json"
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

reset() {
  cat > "$PLUGIN_TAX_CONFIG" <<'JSON'
{"bar":{"layout":{"left":[{"id":"a.first"},{"id":"x.widget","format":"custom","size":3}],
                  "right":[{"id":"b.second"},{"id":"omarchy.clock"}]}},
 "plugins":[], "disabledPlugins":["z.off"], "version":1}
JSON
  echo '["a.first","x.widget","b.second"]' > "$MOCK_IDS"
  rm -rf "$PLUGIN_TAX_STATE"
}

# 1. Full audit: every widget ends where it started, with its settings.
reset; cp "$PLUGIN_TAX_CONFIG" "$tmp/before.json"
out="$("$audit" --shell-pid $$ --any-comm --rounds 1 --sample 0.2 --settle 0.1)"
check "audit emits a result" "grep -q '\"type\":\"result\"' <<<\"\$out\""
check "audit restored shell.json exactly" "[[ \"\$(jq -S . \"$tmp/before.json\")\" == \"\$(jq -S . \"\$PLUGIN_TAX_CONFIG\")\" ]]"
check "three plugins measured" "[[ \$(grep '\"type\":\"result\"' <<<\"\$out\" | jq '.results|length') == 3 ]]"
check "each has 2 on + 1 off samples" "grep '\"type\":\"result\"' <<<\"\$out\" | jq -e 'all(.results[]; (.on|length)==2 and (.off|length)==1)' >/dev/null"
check "journal cleaned up" "[[ ! -e \"\$PLUGIN_TAX_STATE/journal.json\" ]]"
check "last audit persisted" "[[ -s \"\$PLUGIN_TAX_STATE/last-audit.json\" ]]"

# 2. Crash mid-audit (SIGKILL: no trap), then recovery with an unrelated
#    user edit made in between -- recovery must restore x.widget in place
#    and keep the edit.
reset; cp "$PLUGIN_TAX_CONFIG" "$tmp/before.json"
mkdir -p "$PLUGIN_TAX_STATE"; cp "$PLUGIN_TAX_CONFIG" "$PLUGIN_TAX_STATE/snapshot.json"
echo '{"pid":1,"startedAt":0,"current":"x.widget"}' > "$PLUGIN_TAX_STATE/journal.json"
omarchy plugin disable x.widget >/dev/null
jq '.idle = {lock: 42}' "$PLUGIN_TAX_CONFIG" > "$tmp/e" && mv "$tmp/e" "$PLUGIN_TAX_CONFIG"
out="$("$audit" --startup)"
check "recovery reports it" "grep -q '\"type\":\"recovered\"' <<<\"\$out\""
check "x.widget back at left[1] with its settings" "jq -e '.bar.layout.left[1] == {id:\"x.widget\",format:\"custom\",size:3}' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "unrelated edit kept" "jq -e '.idle.lock == 42' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "disabledPlugins untouched" "jq -e '.disabledPlugins == [\"z.off\"]' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "startup prints status" "grep -q '\"type\":\"status\"' <<<\"\$out\""

# 3. Panel Disable -> Re-enable keeps placement and settings.
reset; cp "$PLUGIN_TAX_CONFIG" "$tmp/before.json"
"$audit" --disable x.widget >/dev/null
check "disable removed it" "! jq -e '[.bar.layout[][]|.id]|index(\"x.widget\")' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "status lists it as disabled by us" "\"$audit\" --startup | jq -e 'select(.type==\"status\") | .disabled == [\"x.widget\"]' >/dev/null"
"$audit" --reenable x.widget >/dev/null
check "re-enable restored exactly" "[[ \"\$(jq -S . \"$tmp/before.json\")\" == \"\$(jq -S . \"\$PLUGIN_TAX_CONFIG\")\" ]]"

# 3b. Someone edits shell.json while a plugin is off: the audit keeps the
#     edit and still puts the plugin back in its slot.
reset; rm -f "$PLUGIN_TAX_CONFIG.edited"
out="$(MOCK_EDIT_ON_DISABLE=x.widget "$audit" --shell-pid $$ --any-comm --rounds 1 --sample 0.2 --settle 0.1)"
sleep 0.5
check "mid-audit edit is reported" "grep -q 'changed during the audit' <<<\"\$out\""
check "mid-audit edit kept (idle.lock)" "jq -e '.idle.lock == 7' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "mid-audit edit kept (right reversed)" "jq -e '[.bar.layout.right[].id] == [\"omarchy.clock\",\"b.second\"]' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
check "x.widget still restored at left[1]" "jq -e '.bar.layout.left[1] == {id:\"x.widget\",format:\"custom\",size:3}' \"\$PLUGIN_TAX_CONFIG\" >/dev/null"
rm -f "$PLUGIN_TAX_CONFIG.edited"

# 4. Refuses to measure a process that is not quickshell.
reset
out="$("$audit" --shell-pid $$ 2>&1)"
check "wrong shell pid is refused" "grep -q 'not quickshell' <<<\"\$out\""

# 5. Only one audit at a time.
reset; mkdir -p "$PLUGIN_TAX_STATE"
exec 8>"$PLUGIN_TAX_STATE/lock"; flock 8
out="$("$audit" --shell-pid $$ --any-comm 2>&1)"
check "concurrent audit is refused" "grep -q 'already running' <<<\"\$out\""
exec 8>&-

exit $fail
