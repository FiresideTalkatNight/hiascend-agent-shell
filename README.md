# hiascend-agent

A one-command, offline agent shell for **openEuler x86_64**: [Pi](https://pi.dev)
1.1.0 plus everything needed to operate **[GitCode](https://gitcode.com)**
autonomously — clone, develop, push, and open pull requests — and to work on
Ascend C / CANN operator tasks.

The release tarball bundles **all** runtime pieces:

- the Pi standalone binary (no Node.js or npm required),
- `fd` and `ripgrep` (static musl builds),
- the `gitcode-api` Python package incl. its MCP server (offline wheels for CPython 3.11),
- the `operator-dev` and `gitcode-api` skills, a `gitcode` Pi extension, and prompt templates.

No network access is required to install.

## Requirements

- openEuler 24.03 LTS x86_64 (or another x86_64 Linux with glibc ≥ 2.17)
- `python3.11`, `tar`, `sha256sum`
- root for the default install locations
- `git` and `openssh-clients` for SCM operations (the installer reports them if missing)

## Install

Download the tarball and its checksum from the GitHub release, then:

```bash
sha256sum -c hiascend-agent-<version>-linux-x86_64.tar.gz.sha256
tar xzf hiascend-agent-<version>-linux-x86_64.tar.gz
cd hiascend-agent-<version>-linux-x86_64
./install.sh
```

The installer verifies the package checksums, installs a versioned payload,
creates the Python environment from the bundled wheels, merges the Pi
configuration, and runs `hiascend-agent doctor`.

| Option | Meaning |
|---|---|
| `--prefix DIR` | install root (default `/opt/hiascend-agent`) |
| `--bin-dir DIR` | launcher directory (default `/usr/local/bin`) |
| `--pi-dir DIR` | user Pi directory (default `$HOME/.pi/agent`) |
| `--ghproxy URL` | GitHub proxy prefix, e.g. `https://ghproxy.com/` |
| `--fetch` | download missing Pi/fd/rg assets (needs network/proxy) |
| `--skip-verify` | skip package SHA256 verification |
| `--no-ssh-keygen` | do not generate an SSH key |
| `--no-git-config` | do not set the git identity |
| `--no-doctor` | skip the post-install check |
| `--uninstall` | remove the installation |
| `--purge-config` | with `--uninstall`: remove package entries from Pi config |

> From a source checkout without vendored binaries, use
> `./install.sh --fetch --ghproxy https://ghproxy.com/`. The Python wheels must
> still be present (build the release package first).

## What gets installed

```
/opt/hiascend-agent/
├── <version>/
│   ├── bin/            pi, fd, rg, hiascend-agent
│   ├── pi/             Pi 1.1.0 standalone
│   ├── venv/           gitcode-api CLI + MCP server
│   ├── config/         skills, prompts, extension, settings, mcp
│   └── lib/            merge-config.py, doctor.sh
└── current -> <version>
/usr/local/bin/hiascend-agent
~/.pi/agent/            merged user configuration
```

## First run

1. **SSH key** — the installer prints the public key. Add it at
   <https://gitcode.com/setting/key-ssh>, then verify:

   ```bash
   ssh -T git@gitcode.com
   ```

2. **GitCode token** — export it and verify:

   ```bash
   export GITCODE_ACCESS_TOKEN=...
   hiascend-agent gitcode-api users me
   ```

3. **Check everything**:

   ```bash
   hiascend-agent doctor
   ```

## Usage

```bash
hiascend-agent                 # start Pi (interactive TUI)
hiascend-agent -p "..."        # one-shot prompt
hiascend-agent doctor          # environment + resource self-check
hiascend-agent shell           # login shell with the agent PATH
hiascend-agent gitcode-api ... # bundled GitCode CLI
hiascend-agent version
hiascend-agent uninstall
```

Example:

```bash
hiascend-agent -p "Fork cann/hccl into my namespace, create a branch, add docs/note.md, push it, and open a pull request against master. Report the PR URL."
```

## Bundled resources

| Resource | What it provides |
|---|---|
| `gitcode` extension | `gitcode_whoami`, `gitcode_repo_get`, `gitcode_branches`, `gitcode_fork`, `gitcode_pr_create`, `gitcode_pr_list`, `gitcode_pr_get`, plus `/gitcode` |
| `gitcode-api` skill | full GitCode REST SDK / CLI / MCP usage |
| `operator-dev` skill | Ascend C / CANN code style, review checklist, license headers, layout conventions |
| `prompts/` | system prompt templates (each `.md` becomes a `/command`) |
| `gitcode` MCP server | generic GitCode REST access via `gitcode-api serve` |

## Configuration: system + user layers

Pi has user-level (`~/.pi/agent`) and project-level (`.pi`) configuration. This
package adds a **system layer** under the install prefix and merges it at install
time:

| File | Merge rule |
|---|---|
| `settings.json` | recursive merge; user wins; `skills`/`prompts`/`extensions`/… are unioned with user entries first |
| `mcp.json` | `mcpServers` union; user entry wins on the same name |
| `AGENTS.md` | user file wins; the package one is installed only when absent |

Skills, prompts, and extensions are referenced by **absolute path** into the
install prefix. Upgrading switches the `current` symlink, so bundled resources
update immediately without touching your configuration.

## Upgrade and uninstall

- **Upgrade**: install the newer tarball; `current` switches to the new version
  and your configuration is preserved.
- **Uninstall**:

  ```bash
  hiascend-agent uninstall              # keep ~/.pi/agent
  hiascend-agent uninstall --purge-config
  ```

## Building a release (maintainers)

The repository contains source only; binaries are produced by CI.

```bash
# needs python3.11 + pip (or docker), curl, tar
GHPROXY=https://ghproxy.com/ packaging/build-release.sh
packaging/test-in-container.sh          # offline openEuler install test
```

`packaging/versions.env` pins Pi 1.1.0, fd 10.5.0, ripgrep 15.2.0, and
gitcode-api 1.3.4. The GitHub Actions workflow `.github/workflows/release.yml`
builds the tarball, runs the offline container test, and attaches the package and
its SHA256 to the release.
