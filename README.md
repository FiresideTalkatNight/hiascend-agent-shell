# hiascend-agent-shell

An interactive **agent shell** in a container: the [Pi](https://pi.dev) coding
agent plus everything it needs to operate **[GitCode](https://gitcode.com)**
autonomously — clone, develop, push, and open pull requests — for automating
repository-based engineering tasks.

## What's inside

| Component | Provides |
|---|---|
| Pi — `@earendil-works/pi-coding-agent` | the agent harness (interactive TUI, one-shot, JSON, RPC) |
| `git`, `git-lfs`, `openssh-client` | clone / branch / commit / push over SSH |
| `gitcode-api[mcp]` | GitCode REST SDK, the `gitcode-api` CLI, and an MCP server |
| `uv`, `python3` | on-demand Python tooling for the agent |
| `gitcode` extension | native `gitcode_*` tools and the `/gitcode` command |
| Built-in skills | `gitcode-api` (GitCode API) and `operator-dev` (Ascend C / CANN operator development) |
| System config | `/etc/pi/agent` — Pi defaults, merged with your mounted `~/.pi/agent` at startup |

Runs as non-root user **`agent`** (uid/gid 1000), with working directory
`/workspace`.

## Requirements

- Docker (or a compatible OCI runtime)
- Outbound network access to `gitcode.com` (HTTPS and SSH) and to your LLM provider

## Build

```bash
docker build -t hiascend-agent-shell:latest .
```

## Run

```bash
docker run --rm -it \
  -e GITCODE_ACCESS_TOKEN \
  -e DEEPSEEK_API_KEY \
  -v "$PWD/pi-agent:/home/agent/.pi/agent" \
  -v agent-shell-ssh:/home/agent/.ssh \
  -v "$PWD/workspace:/workspace" \
  hiascend-agent-shell:latest
```

The container opens a shell. Start the agent inside it:

```bash
pi                      # interactive TUI
pi -p "…"               # one-shot prompt
pi --mode rpc           # JSON/RPC protocol, for automation
```

`run.sh` wraps the `docker run` command above; it forwards provider keys from the
environment and defaults to `$PWD/pi-agent`, `$PWD/workspace` and the
`agent-shell-ssh` volume.

## Mounts

| Container path | Purpose |
|---|---|
| `/home/agent/.ssh` | SSH identity + `known_hosts`. **Generated on first run**; keep it in a volume so the key stays stable. |
| `/home/agent/.pi/agent` | Pi configuration (user layer): provider credentials, `settings.json`, `models.json`, `mcp.json`, your skills/extensions, sessions. Merged with the image's system layer at startup. |
| `/workspace` | your repository checkout |

## Environment

| Variable | Purpose |
|---|---|
| `GITCODE_ACCESS_TOKEN` | GitCode REST / CLI / MCP authentication |
| `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, … | LLM provider credentials |
| `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL` | commit identity (default `hiascend-agent`) |
| `GITCODE_SSH_HOST` | SSH host to configure (default `gitcode.com`) |
| `AGENT_SHELL_QUIET=1` | suppress the startup banner |

## Authentication

1. **SSH — required for push/pull.** On first start the container generates
   `~/.ssh/id_ed25519` and prints the public key. Add it at
   <https://gitcode.com/setting/key-ssh>, then verify inside the container:

   ```bash
   ssh -T git@gitcode.com
   ```

2. **GitCode token — required for forks and pull requests.** Export
   `GITCODE_ACCESS_TOKEN`, then verify:

   ```bash
   gitcode-api users me
   ```

## Operating GitCode

The agent is given first-class GitCode tools, so it does not have to hand-write
API calls:

| Tool | Purpose |
|---|---|
| `gitcode_whoami` | the authenticated user |
| `gitcode_repo_get` | repository metadata (default branch, clone URLs) |
| `gitcode_branches` | list branches |
| `gitcode_fork` | fork a repository into your namespace (idempotent) |
| `gitcode_pr_create` | open a pull request |
| `gitcode_pr_list` | list pull requests |
| `gitcode_pr_get` | pull request details |

Also available: the `/gitcode` command (shows the authenticated user). Repository
work — clone, branch, commit, push — uses the agent's built-in shell tool with
`git`. Anything not covered by the tools is reachable through the bundled
`gitcode` MCP server or the `gitcode-api` CLI, and the `gitcode-api` skill
documents the full API surface.

Example:

```bash
pi -p "Fork cann/hccl into my namespace, create a branch, add docs/note.md, \
       push it, and open a pull request against master. Report the PR URL."
```

## Configuration

Pi configuration has two layers, merged at container startup:

| Layer | Location | Contents |
|---|---|---|
| System (image) | `/etc/pi/agent` | agent instructions, default settings, the GitCode MCP server, built-in skills (`gitcode-api`, `operator-dev`), prompt templates, the `gitcode` extension |
| User (yours) | `/home/agent/.pi/agent` | credentials, model overrides, your own skills/prompts/extensions, sessions |

- `settings.json` and `mcp.json` are merged (your values win; resource lists are
  unioned with your entries first). Your `AGENTS.md` takes precedence over the
  system one.
- System resources are loaded from `/etc/pi/agent` by absolute path, so image
  upgrades apply immediately and are never copied into your configuration.
- No provider or model is baked in. Supply credentials through environment
  variables or a mounted `~/.pi/agent` (`auth.json`, `models.json`), and select a
  model with `--model <provider>/<id>`.
- The shipped settings enable the `codemode` tool (batch tool calls from a
  script).

## Security

- Runs as a non-root user. Pi deliberately has no permission prompts, so the
  **container is the security boundary** — expose only the directories and
  credentials the task needs.
- Credentials are provided at run time (environment variables or mounted files)
  and are never stored in the image.
