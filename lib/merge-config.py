#!/usr/bin/env python3
"""Merge the package's system Pi config into the user's agent directory.

Merge semantics (user always wins):
  * settings.json : recursive merge; resource arrays are unioned, user first
  * mcp.json      : mcpServers union, user entry wins on the same name
  * AGENTS.md     : installed only when the user does not have one

Also supports `--remove --prefix DIR` for uninstall/purge.

Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile

ARRAY_KEYS = ("skills", "prompts", "extensions", "themes", "packages")


def warn(message: str) -> None:
    print(f"[merge-config] warning: {message}", file=sys.stderr)


def read_json(path: str):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return None
    except Exception as exc:  # noqa: BLE001
        warn(f"cannot parse {path}: {exc}")
        return "invalid"


def write_json(path: str, data) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".merge-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def deep_merge(base, override):
    """Recursively merge dicts; `override` wins. Non-dict values are replaced."""
    if isinstance(base, dict) and isinstance(override, dict):
        merged = dict(base)
        for key, value in override.items():
            merged[key] = deep_merge(base[key], value) if key in base else value
        return merged
    return override


def unique(sequence):
    result = []
    for item in sequence:
        if item not in result:
            result.append(item)
    return result


def merge_settings(system, user):
    merged = deep_merge(system, user)
    for key in ARRAY_KEYS:
        merged[key] = unique((user.get(key) or []) + (system.get(key) or []))
    return merged


def merge(system_dir: str, user_dir: str) -> None:
    os.makedirs(user_dir, exist_ok=True)

    system_settings = read_json(os.path.join(system_dir, "settings.json"))
    if system_settings not in (None, "invalid"):
        user_settings = read_json(os.path.join(user_dir, "settings.json"))
        if user_settings == "invalid":
            warn("keeping invalid user settings.json (not merging)")
        else:
            write_json(
                os.path.join(user_dir, "settings.json"),
                merge_settings(system_settings, user_settings or {}),
            )

    system_mcp = read_json(os.path.join(system_dir, "mcp.json"))
    if system_mcp not in (None, "invalid"):
        user_mcp = read_json(os.path.join(user_dir, "mcp.json"))
        if user_mcp == "invalid":
            warn("keeping invalid user mcp.json (not merging)")
        else:
            user_mcp = user_mcp or {}
            merged = {
                "mcpServers": {
                    **(system_mcp.get("mcpServers") or {}),
                    **(user_mcp.get("mcpServers") or {}),
                }
            }
            write_json(os.path.join(user_dir, "mcp.json"), merged)

    source_agents = os.path.join(system_dir, "AGENTS.md")
    target_agents = os.path.join(user_dir, "AGENTS.md")
    if os.path.isfile(source_agents) and not os.path.exists(target_agents):
        try:
            shutil.copyfile(source_agents, target_agents)
        except Exception as exc:  # noqa: BLE001
            warn(f"cannot install {target_agents}: {exc}")


def remove_prefix(user_dir: str, prefix: str) -> None:
    settings_path = os.path.join(user_dir, "settings.json")
    settings = read_json(settings_path)
    if isinstance(settings, dict):
        for key in ARRAY_KEYS:
            if isinstance(settings.get(key), list):
                settings[key] = [
                    entry
                    for entry in settings[key]
                    if not (isinstance(entry, str) and entry.startswith(prefix))
                ]
        write_json(settings_path, settings)

    mcp_path = os.path.join(user_dir, "mcp.json")
    mcp = read_json(mcp_path)
    if isinstance(mcp, dict) and isinstance(mcp.get("mcpServers"), dict):
        servers = {
            name: server
            for name, server in mcp["mcpServers"].items()
            if not (
                isinstance(server, dict)
                and isinstance(server.get("command"), str)
                and server["command"].startswith(prefix)
            )
        }
        mcp["mcpServers"] = servers
        write_json(mcp_path, mcp)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--system", help="package system config directory")
    parser.add_argument("--user", default=os.path.expanduser("~/.pi/agent"), help="user agent directory")
    parser.add_argument("--remove", action="store_true", help="remove package entries instead of merging")
    parser.add_argument("--prefix", help="install prefix to remove (with --remove)")
    args = parser.parse_args()

    if args.remove:
        if not args.prefix:
            parser.error("--remove requires --prefix")
        remove_prefix(args.user, args.prefix)
        return 0

    if not args.system:
        parser.error("--system is required unless --remove is used")
    merge(args.system, args.user)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
