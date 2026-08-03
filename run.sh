#!/usr/bin/env bash
# Record only this top-level parent; nested run.sh calls inherit the guard.
# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/_code/_maintenance/record-script-usage.sh"
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="${SCRIPT_DIR##*/}"
SCRIPT_NAME="${SCRIPT_NAME^}"

if [[ -t 1 ]]; then
    printf '\033]0;%s [Med/Low Effort]\007' "$SCRIPT_NAME"
fi

SAVED_DIR="/tumble-storage/tumble-script/_saved/sol-luna"
SOL_MODEL="opencode/gpt-5.6-sol"
LUNA_MODEL="opencode/gpt-5.6-luna"
MAX_REVIEW_CYCLES=3

set_sol_luna_tui_variants() {
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
    local state_file="$state_dir/model.json"
    local temporary_file

    [[ -f "$state_file" ]] || return 0
    temporary_file="$(mktemp "$state_dir/model.json.XXXXXX")"
    if jq --arg sol "$SOL_MODEL" --arg luna "$LUNA_MODEL" \
        '.variant = (.variant // {}) | .variant[$sol] = "medium" | .variant[$luna] = "low"' \
        "$state_file" > "$temporary_file"; then
        chmod --reference="$state_file" "$temporary_file"
        mv -f -- "$temporary_file" "$state_file"
        return 0
    fi

    rm -f -- "$temporary_file"
    return 1
}

usage() {
    cat <<'EOF'
Usage: ./run.sh [OPENCODE ARGUMENTS]

Launch an opencode session with Sol (medium-effort review) and
Luna (low-effort implementation), both via the Codex subscription.

Arguments are passed to opencode. For example:
  ./run.sh models opencode

Inside OpenCode:
  /implement  Implement the plan with Luna
  /review     Start review with Sol, repair with Luna, and re-review
  /repair     Apply the latest Sol Review findings
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if ! command -v opencode >/dev/null 2>&1; then
    printf 'ERROR: opencode is not available on PATH.\n' >&2
    exit 1
fi

umask 077
RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
RUN_DIR="$SAVED_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

WORKSPACE_DIR="$PWD"
GIT_ROOT="$(git -C "$WORKSPACE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
BASE_COMMIT=""
if [[ -n "$GIT_ROOT" ]]; then
    BASE_COMMIT="$(git -C "$GIT_ROOT" rev-parse HEAD 2>/dev/null || true)"
    git -C "$GIT_ROOT" status --porcelain=v1 > "$RUN_DIR/baseline-status.txt"
    git -C "$GIT_ROOT" diff --name-only > "$RUN_DIR/baseline-unstaged-files.txt"
    git -C "$GIT_ROOT" diff --cached --name-only > "$RUN_DIR/baseline-staged-files.txt"
    BASELINE_KIND="git"
else
    printf 'No Git repository detected in %s; review and repair quality gates will be disabled.\n' "$WORKSPACE_DIR" >&2
    : > "$RUN_DIR/baseline-status.txt"
    : > "$RUN_DIR/baseline-unstaged-files.txt"
    : > "$RUN_DIR/baseline-staged-files.txt"
    BASELINE_KIND="non-git"
fi

cat > "$RUN_DIR/context.txt" <<EOF
Sol-Luna run context
Run ID: $RUN_ID
Workspace: $WORKSPACE_DIR
Git root: ${GIT_ROOT:-none}
Base commit: ${BASE_COMMIT:-none}
Baseline kind: $BASELINE_KIND
Baseline status: $RUN_DIR/baseline-status.txt
Baseline unstaged files: $RUN_DIR/baseline-unstaged-files.txt
Baseline staged files: $RUN_DIR/baseline-staged-files.txt
Maximum review/repair cycles: $MAX_REVIEW_CYCLES
EOF

export SOL_LUNA_RUN_ID="$RUN_ID"
export SOL_LUNA_RUN_DIR="$RUN_DIR"
export SOL_LUNA_WORKSPACE="$WORKSPACE_DIR"
export SOL_LUNA_GIT_ROOT="$GIT_ROOT"
export SOL_LUNA_BASE_COMMIT="$BASE_COMMIT"
export SOL_LUNA_BASELINE_KIND="$BASELINE_KIND"

if ! opencode models opencode | grep -Fxq "$SOL_MODEL"; then
    printf 'ERROR: required review model is unavailable: %s\n' "$SOL_MODEL" >&2
    exit 1
fi

if ! opencode models opencode | grep -Fxq "$LUNA_MODEL"; then
    printf 'ERROR: required implement model is unavailable: %s\n' "$LUNA_MODEL" >&2
    exit 1
fi

OPENCODE_CONFIG_CONTENT="$(cat <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "default_agent": "luna-implement",
  "agent": {
    "luna-implement": {
      "description": "Explore and implement with Luna at low reasoning effort.",
      "mode": "primary",
      "model": "$LUNA_MODEL",
      "variant": "low",
      "reasoningEffort": "low",
      "prompt": "You are Luna Implement. Use the agreed plan and conversation context to explore the repository and make the requested changes. Read \$SOL_LUNA_RUN_DIR/context.txt before editing. Do not repeat broad planning; identify only the details needed to implement and verify the work. Preserve pre-existing changes recorded in \$SOL_LUNA_RUN_DIR/baseline-status.txt. Run relevant tests or checks. In a Git repository, create a build checkpoint commit named 'sol-luna: build checkpoint' only when the files you changed do not overlap pre-existing changed files; otherwise leave the work uncommitted and report the overlap. Never push.",
      "steps": 30
    },
    "sol-review": {
      "description": "Review Luna's work against the agreed plan with Sol at medium reasoning effort. Read-only; delegates repairs to Luna Repair.",
      "mode": "primary",
      "model": "$SOL_MODEL",
      "variant": "medium",
      "reasoningEffort": "medium",
      "prompt": "You are Sol Review. Review the implementation against the agreed plan, acceptance criteria, and repository reality. Read \$SOL_LUNA_RUN_DIR/context.txt, the baseline status files, relevant files, git status, git diff, and git diff \$SOL_LUNA_BASE_COMMIT when a base commit exists. Run safe verification checks as needed. You are read-only: never edit or write files yourself. Report each finding with severity, file and line, evidence, whether it is a plan deviation or bug, and a concrete repair instruction. If findings exist and this is a Git repository, delegate them to the luna-repair subagent. Ask that subagent to preserve baseline changes, avoid overlapping files when checkpointing, run tests, and never push. After repair, inspect the new diff and re-review. Repeat for at most \$MAX_REVIEW_CYCLES cycles. Stop and report unresolved findings or unsafe overlaps. If the implementation satisfies the plan and checks, report CLEAN.",
      "steps": 40,
      "permission": {
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "bash": {
          "git status*": "allow",
          "git diff*": "allow",
          "git log*": "allow",
          "git show*": "allow",
          "git rev-parse*": "allow",
          "git ls-files*": "allow",
          "git check-ignore*": "allow",
          "*": "ask"
        },
        "task": "allow",
        "webfetch": "allow",
        "edit": "deny",
        "write": "deny",
        "todowrite": "deny"
      }
    },
    "luna-repair": {
      "description": "Implement Sol Review's concrete findings with Luna at low reasoning effort.",
      "mode": "subagent",
      "model": "$LUNA_MODEL",
      "variant": "low",
      "reasoningEffort": "low",
      "prompt": "You are Luna Repair. Implement only the concrete findings supplied by Sol Review. Read \$SOL_LUNA_RUN_DIR/context.txt and \$SOL_LUNA_RUN_DIR/baseline-status.txt first. Preserve all pre-existing changes and do not edit files unrelated to the findings. Run relevant tests or checks after editing. In a Git repository, create a repair checkpoint commit named 'sol-luna: repair checkpoint' only when your changed files do not overlap baseline-changed files; otherwise leave the work uncommitted and report the overlap. Never push.",
      "steps": 30
    }
  },
  "command": {
    "implement": {
      "description": "Implement the plan above with Luna",
      "agent": "luna-implement",
      "template": "Implement the agreed plan from this conversation. If there is no agreed plan, ask the user to start planning first."
    },
    "review": {
      "description": "Review the implementation with Sol, repair findings with Luna, and re-review",
      "agent": "sol-review",
      "template": "Review the current implementation against the agreed plan. Use the recorded run context and perform the bounded review/repair/re-review workflow. If there is no implementation or agreed plan, explain what is missing."
    },
    "repair": {
      "description": "Apply Sol Review findings with Luna",
      "agent": "luna-repair",
      "template": "Implement the latest Sol Review findings in this conversation. If there are no concrete findings, ask for a Sol Review first."
    }
  },
  "provider": {
    "opencode": {
      "models": {
        "gpt-5.6-sol": {
          "reasoning": true,
          "variants": {
            "medium": {
              "reasoningEffort": "medium"
            }
          }
        },
        "gpt-5.6-luna": {
          "reasoning": true,
          "variants": {
            "low": {
              "reasoningEffort": "low"
            }
          }
        }
      }
    }
  }
}
EOF
)"
export OPENCODE_CONFIG_CONTENT

if ! set_sol_luna_tui_variants; then
    printf 'WARNING: could not set the persisted Sol and Luna OpenCode variants.\n' >&2
fi

printf 'Launching opencode %s with Sol (medium-effort review) + Luna (low-effort implement)...\n\n' "$(opencode --version)"

if opencode "$@"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    printf '\nSuccess.\n'
else
    printf '\nExited with code %d.\n' "$EXIT_CODE"
fi

if [[ -t 1 ]]; then
    printf 'Press any key to exit...'
    read -r -n 1 -s /dev/tty
fi

exit $EXIT_CODE
