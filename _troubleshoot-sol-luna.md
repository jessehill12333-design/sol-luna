# sol-luna — troubleshooting log

This file contains the troubleshooting history formerly embedded in the repository README.

## Open issues


### Sol and Luna effort labels use persisted variants

**Status:** WORKAROUND

**Shortcut:** `/tumble-storage/tumble-shortcut/ai-harness/sol-luna.desktop`

**Symptom:** OpenCode can display a persisted per-model variant instead of the effort configured by the launcher.

**Root cause:** OpenCode 1.18.4 initializes the TUI from the model entries in `~/.local/state/opencode/model.json`. The file had no persisted variants for `opencode/gpt-5.6-sol` or `opencode/gpt-5.6-luna`.

**Fix:** Remove the legacy nested `options.reasoning` settings, retain direct `reasoningEffort` and named variants, and set Sol to `medium` and Luna to `low` in the persisted OpenCode model state before launch.

**Verify:** `./run.sh debug config` resolves Sol Review to `medium` and Luna Implement/Repair to `low`; a fresh Sol Review TUI session rendered `medium`. Open a fresh Luna session and confirm it renders `low` before moving this entry to Resolved issues.
