# AGENTS.md — sol-luna

## Purpose

Launch an opencode terminal session using Sol (medium-effort reasoning) as
reviewer and Luna (low-effort reasoning) as implementer/repair agent, both
via the Codex subscription.

## Editing rules

- Keep `run.sh` as the stable entry point; do not rename or replace it.
- Do not add comments unless explicitly requested.
- Do not commit secrets or API keys to the repository.
- The opencode config is generated at runtime from a heredoc in `run.sh`; edit the heredoc to change agent settings.
- Preserve the Implement -> Review -> Repair workflow and its three-cycle review limit.
- Treat the run context under `_saved/sol-luna/runs/` as the baseline source for dirty-worktree handling.
- Never push from an agent or launcher workflow.
