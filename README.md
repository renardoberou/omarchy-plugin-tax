# Plugin Tax

An Omarchy shell plugin that watches the shell's own idle CPU headroom and,
on demand, finds out which enabled third-party plugin is spending it.

## Why

Omarchy plugins are QML loaded into one long-lived, unsandboxed `quickshell`
process — there's no per-plugin PID, so the OS scheduler can't hand you a
"this plugin costs X% CPU" number the way `top` can for a normal process.
The only reliable way to attribute cost is the manual test that already
caught a real CPU leak on this machine once (a wallpaper shader plugin
quietly burning ~16% CPU at idle): disable the plugin, compare whole-shell
CPU before and after, re-enable it. This plugin automates that test and
runs it across every enabled third-party plugin instead of one at a time
by hand.

## What it does

- **Bar pill (continuous, free):** every 20s, samples the shell process's
  CPU over a short window (the `top -bn2` method: two `/proc/[pid]/stat`
  reads across a sleep). Tracks a rolling "lean baseline" — the lowest
  reading seen recently — and shows current headroom above it. This is a
  whole-shell signal, not per-plugin; it just tells you *something* is
  costing more than usual.
- **Run audit (on demand, precise):** disables each enabled, third-party,
  non-`bar`-kind plugin one at a time, samples before/after, re-enables it,
  moves on. Ranks the results by CPU delta and flags anything ≥3%. This is
  genuinely disruptive — each plugin blinks off for a few seconds — so it's
  a button, not a timer. Always restores everything it touched, even on
  failure or interrupt (bash `trap`).

First-party plugins and full-bar replacements (`kind: "bar"`) are excluded
from the audit in this v1 — toggling core Omarchy UI is a different, worse
kind of disruptive than blinking a third-party widget off.

## Structure

```
manifest.json         schema + two entry points (service, bar-widget)
Service.qml            headless: sampling timer, rolling baseline, audit orchestration
BarWidget.qml           bar pill + popup panel, reads Service via bar.shell.serviceFor(id)
Model.js               pure parsing/formatting/ranking logic (node-testable, no I/O)
bin/plugin-tax-sample   one CPU/RSS sample of the shell process (own $PPID)
bin/plugin-tax-audit    the disable → sample → re-enable loop, emits ranked JSON
```

## Local dev

```
omarchy plugin validate .
ln -sfn "$PWD" ~/.config/omarchy/plugins/renardoberou.plugin-tax
omarchy plugin enable renardoberou.plugin-tax
omarchy restart shell
journalctl --user -t omarchy-shell --since "1 minute ago" | grep plugin-tax
```

`node -e "require('./Model.js')..."` exercises the pure logic without
touching the shell at all.

## Known limits

- No persistence: idle-glance history resets on every shell restart.
- The continuous pill is whole-shell only; only the audit attributes cost
  to a specific plugin.
- A plugin that costs CPU only in a GPU shader/render thread rather than
  the main QML thread may still show up correctly here (the sample reads
  the whole process, which includes the render thread) — this hasn't been
  tested against a live example since the machine's one known offender was
  already removed before this plugin existed.
