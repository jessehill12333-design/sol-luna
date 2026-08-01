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

## Resolved issues

### Runtime checkpoint policy also blocked authorized maintenance publication

**Status:** FIXED 2026-08-01

**Symptom:** A repository rule correctly prevented Sol/Luna runtime agents from
pushing their automatic checkpoint commits, but its broad wording also blocked
an independent maintenance session after the user explicitly requested GitHub
publication.

**Root cause:** The policy said no agent or launcher workflow could push without
distinguishing embedded Sol/Luna runtime agents from a separately authorized
repository-maintenance workflow.

**Fix:** Keep runtime checkpoint pushes prohibited and explicitly allow a
separate maintenance workflow to publish only after direct user authorization.

**Verify:** The README and `AGENTS.md` now describe the same boundary; the
pending documentation commit can be published by this authorized maintenance
session while Sol/Luna's generated runtime prompts continue to say `Never push`.
