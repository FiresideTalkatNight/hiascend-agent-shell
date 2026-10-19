---
name: operator-dev
description: >
  Use when developing, reviewing, or fixing Ascend C / CANN operator code
  (op_host, op_kernel, op_api, tiling) or preparing operator contributions.
  Covers CANN code style, common review fixes, license headers, directory
  layout, and documentation conventions for community operator repositories.
---

# Operator development (Ascend C / CANN)

Use this skill when working on a CANN operator repository: implementing or
modifying a kernel, reviewing a contribution, fixing review comments, or
preparing a pull request.

## Workflow

1. Locate the operator directory and read its README/design notes first.
2. Read only the reference below that matches the work at hand.
3. Keep the change scoped to the operator; do not modify other operators.
4. Build and run the repository's unit tests when the environment supports it.
5. Re-check the change against `references/review-checklist.md` before finishing.

## Non-negotiable conventions

- Do not hard-code `BLOCK_SIZE = 32`; obtain it from the platform API.
- Always brace single-line `if`/`for` bodies.
- Null-check every pointer before use and before dereference.
- Use `DataCopyPad` for non-32-byte-aligned transfers.
- Guard against division by zero and non-positive core/UB sizes.
- Print an error log before returning failure.
- Add the required CANN license header to every new `.cpp`/`.h`/`.py`/`.sh` file.
- Keep only the operator's own kernel/host/tiling files; remove redundant
  config, graph, and staging files.

## References

- `references/code-style.md` — 13 common code-style problems, each with a
  wrong/right example and rationale.
- `references/review-checklist.md` — review and remediation checklist
  (tilingKey, `constexpr`, null checks, division-by-zero, logging, indentation,
  C++ casts, include guards, naming, `Cast` RoundMode, function size).
- `references/license-headers.md` — required license headers for C++ and
  Python/shell sources.
- `references/layout-and-examples.md` — expected operator directory/file layout
  and reference operators (Abs, Sqrt, `add_example`).
- `references/docs.md` — documentation and per-round log conventions.
