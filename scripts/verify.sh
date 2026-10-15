#!/usr/bin/env bash
# =============================================================================
# Phase-1 end-to-end verification: fork -> develop -> push -> pull request,
# driven from inside the container.
#
# Run this from the VM guest (bash /work/scripts/verify.sh).
#
# Prerequisites (the two "pause points"):
#   A. The container's SSH public key must be registered on GitCode.
#      Run once, copy the printed key to https://gitcode.com/setting/key-ssh,
#      then re-run. The key is kept in a named volume, so it survives re-runs.
#   B. A GitCode token file and a sandbox repository to act on.
#
# Environment:
#   SANDBOX_OWNER   (required)  upstream owner of the sandbox repo, e.g. cann
#   SANDBOX_REPO    (required)  upstream repo name,               e.g. hccl
#   BASE_BRANCH     (default master)
#   BRANCH          (default agent-shell-e2e-<UTC timestamp>)
#   TOKEN_FILE      (default ./secrets/gitcode_token)
#   IMAGE           (default hiascend/agent-shell:phase1)
#   CONTAINER       (default agent-shell-e2e)
#   CFG_DIR         (default ./e2e/pi-agent)
#   SSH_VOLUME      (default agent-shell-ssh)
#   WORKSPACE_DIR   (default ./e2e/workspace)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-hiascend-agent-shell:latest}"
CONTAINER="${CONTAINER:-agent-shell-e2e}"
SANDBOX_OWNER="${SANDBOX_OWNER:?set SANDBOX_OWNER (upstream owner of the sandbox repo)}"
SANDBOX_REPO="${SANDBOX_REPO:?set SANDBOX_REPO (upstream repo name)}"
BASE_BRANCH="${BASE_BRANCH:-master}"
BRANCH="${BRANCH:-agent-shell-e2e-$(date -u +%Y%m%d%H%M%S)}"
TOKEN_FILE="${TOKEN_FILE:-./secrets/gitcode_token}"
CFG_DIR="${CFG_DIR:-./e2e/pi-agent}"
SSH_VOLUME="${SSH_VOLUME:-agent-shell-ssh}"
WORKSPACE_DIR="${WORKSPACE_DIR:-./e2e/workspace}"

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ -s "$TOKEN_FILE" ] || die "token file not found or empty: $TOKEN_FILE
write the GitCode access token to that file and re-run."
GITCODE_ACCESS_TOKEN="$(tr -d '\r\n' <"$TOKEN_FILE")"
export GITCODE_ACCESS_TOKEN

mkdir -p "$CFG_DIR" "$WORKSPACE_DIR"
# The container runs as uid 1000; best-effort fix ownership of bind mounts.
chown -R 1000:1000 "$CFG_DIR" "$WORKSPACE_DIR" 2>/dev/null || true
docker volume inspect "$SSH_VOLUME" >/dev/null 2>&1 || docker volume create "$SSH_VOLUME" >/dev/null

say "build"
docker build -t "$IMAGE" .

say "start container"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" \
  -e GITCODE_ACCESS_TOKEN \
  -e AGENT_SHELL_QUIET=1 \
  -e GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-hiascend-agent}" \
  -e GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-hiascend-agent@localhost}" \
  -v "$CFG_DIR:/home/agent/.pi/agent" \
  -v "$SSH_VOLUME:/home/agent/.ssh" \
  -v "$(cd "$WORKSPACE_DIR" && pwd):/workspace" \
  "$IMAGE" sleep infinity >/dev/null
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

exec_in() { docker exec "$CONTAINER" bash -lc "$1"; }

say "pause point A: SSH authentication"
PUBKEY="$(exec_in 'cat ~/.ssh/id_ed25519.pub')"
if ! exec_in 'ssh -o BatchMode=yes -o ConnectTimeout=8 -T git@gitcode.com' 2>&1 | grep -qi 'permission denied'; then
  echo "GitCode SSH: authenticated"
else
  cat <<EOF

  GitCode SSH is not authenticated yet.
  Add this public key at https://gitcode.com/setting/key-ssh :

$(printf '%s\n' "$PUBKEY" | sed 's/^/      /')

  Then re-run this script (the key persists in the '$SSH_VOLUME' volume).
EOF
  exit 2
fi

say "REST API identity"
ME="$(exec_in 'gitcode-api users me --compact | jq -r .login')"
echo "authenticated as: $ME"

say "fork $SANDBOX_OWNER/$SANDBOX_REPO"
exec_in "gitcode-api repos fork --owner '$SANDBOX_OWNER' --repo '$SANDBOX_REPO' >/dev/null 2>&1 || true"
FORK_FULL=""
for _ in $(seq 1 10); do
  FORK_FULL="$(exec_in "gitcode-api repos get --owner '$ME' --repo '$SANDBOX_REPO' --compact 2>/dev/null | jq -r '.full_name' 2>/dev/null" || true)"
  case "$FORK_FULL" in ''|null) sleep 3 ;; *) break ;; esac
done
case "$FORK_FULL" in ''|null) die "fork of $SANDBOX_OWNER/$SANDBOX_REPO was not created";; esac
echo "fork: $FORK_FULL"

say "clone fork, create branch, commit, push"
exec_in "set -e
  cd /workspace
  rm -rf '$SANDBOX_REPO'
  git clone \"git@gitcode.com:$ME/$SANDBOX_REPO.git\" '$SANDBOX_REPO'
  cd '$SANDBOX_REPO'
  git remote add upstream \"git@gitcode.com:$SANDBOX_OWNER/$SANDBOX_REPO.git\"
  git fetch upstream --quiet || true
  if git rev-parse --verify --quiet 'upstream/$BASE_BRANCH' >/dev/null; then
    git switch -c '$BRANCH' 'upstream/$BASE_BRANCH'
  else
    echo 'note: upstream/$BASE_BRANCH not found; branching from the fork HEAD'
    git switch -c '$BRANCH'
  fi
  mkdir -p e2e
  echo \"agent-shell e2e \$(date -u +%FT%TZ)\" >> e2e/agent-shell.md
  git add -A
  git commit -m 'chore(e2e): verify agent-shell fork/push/PR pipeline'
  git push -u origin '$BRANCH'"

say "open pull request"
exec_in "gitcode-api pulls create \
  --owner '$SANDBOX_OWNER' --repo '$SANDBOX_REPO' \
  --title '[e2e] agent-shell fork/push/PR verification' \
  --head '$ME:$BRANCH' \
  --base '$BASE_BRANCH' \
  --body 'Automated Phase-1 verification from the hiascend-agent shell. Safe to close.'" \
  | tee /tmp/pr-create.json

say "verify pull request exists"
exec_in "gitcode-api pulls list --owner '$SANDBOX_OWNER' --repo '$SANDBOX_REPO' --state open --compact" \
  | jq -r --arg b "$BRANCH" '.[] | select(.source_branch==$b) | "PR #\(.number) \(.title) -> \(.html_url // .url)"'

say "gitcode extension selftest (same code path as the Pi tools)"
exec_in "GITCODE_SELFTEST_OWNER='$SANDBOX_OWNER' GITCODE_SELFTEST_REPO='$SANDBOX_REPO' \
  node /home/agent/.pi/agent/extensions/gitcode/selftest.ts"

say "done"
echo "fork   : https://gitcode.com/$ME/$SANDBOX_REPO"
echo "branch : $BRANCH"
echo "pr json: /tmp/pr-create.json (in container)"
