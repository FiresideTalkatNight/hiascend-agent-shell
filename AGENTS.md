# AGENTS.md — hiascend-agent-shell 开发指南

> 本文件面向**本镜像/工具的开发者与接手开发的 agent**，记录设计意图、目录结构、
> 关键取舍与协作约定。
>
> - 运行期 agent 的指令在 **`pi-defaults/AGENTS.md`**（会被注入容器的 `~/.pi/agent/`），
>   本文件与之不同、不要混淆。
> - 面向使用者的文档在 **`README.md`**（不含开发/测试环境内容）。
> - 第一阶段的过程与验证记录在仓库根的 **`../NOTES.md`**。

---

## 1. 项目目标与现状

- **目标**：提供一个**交互式 agent shell 容器**，让 LLM agent（[Pi](https://pi.dev)）能够
  自主操作 **GitCode**，完成 `fork → 拉取开发 → 推送 → 提 PR`，用于自动化「基于仓库的
  工程任务」（例如算子开发任务 hccl4py 这类需要多仓、多 PR、含设计文档与测试代码的任务）。
- **现状**：第一阶段**已完成并验证**——脚本驱动（`scripts/verify.sh`）与 LLM 驱动（真实模型）
  两种模式下的完整闭环均通过。
- **镜像**：`hiascend-agent-shell:latest`，构建上下文为 `work/`。

### 后续方向（backlog）

- 叠加 **CANN/Ascend** 运行时层（A3/A5，CANN ≥ 9.2.0），支持真机编译/运行算子任务。
- **多仓库/多 PR 编排**：设计文档 + 测试代码 + 功能代码，跨 `hccl`/`hcomm` 等仓。
- **PR 迭代闭环**：读取评审意见与 CI 结果，自动修订并更新 PR。
- 可选 **`permission-gate` 扩展**做风险命令确认；`linux/arm64` 构建；镜像瘦身。

---

## 2. 架构总览

```
┌───────────────────────────────────────────────────────────────┐
│ node:24-bookworm-slim                                          │
│  ├─ pi  (@earendil-works/pi-coding-agent, pinned)   agent      │
│  ├─ git / git-lfs / openssh-client                  harness    │
│  ├─ /opt/venv  →  gitcode-api[mcp] CLI + MCP server + uv       │
│  ├─ /workspace                                       (非 root) │
│  └─ entrypoint.sh  →  SSH key / git identity / Pi 配置 → exec  │
└───────────────────────────────────────────────────────────────┘
        ▲ mounts: ~/.ssh (volume) · ~/.pi/agent (config) · /workspace
        ▲ env:    GITCODE_ACCESS_TOKEN · <PROVIDER>_API_KEY · GIT_AUTHOR_*
```

| 组件 | 作用 |
|---|---|
| Pi | agent harness（交互 TUI / `-p` 一次性 / JSON / RPC） |
| git + openssh | clone / branch / commit / push（SSH） |
| `gitcode-api[mcp]` | GitCode REST SDK、`gitcode-api` CLI、MCP server |
| `gitcode` 扩展 | 原生 `gitcode_*` 工具 + `/gitcode` 命令（`pi-defaults/extensions/gitcode/`） |
| `gitcode-api` skill | 完整 API/用法说明（`pi-defaults/skills/gitcode-api/`） |

---

## 3. 目录结构

```
work/
├── Dockerfile                  # 镜像定义（本项目的核心产物）
├── entrypoint.sh               # 运行期初始化：SSH / git / Pi 配置，再 exec CMD
├── .dockerignore               # 排除 secrets / e2e / workspace / .git
├── README.md                   # ★ 面向使用者（发布文档）
├── AGENTS.md                   # ★ 本文件：面向开发者/agent
├── run.sh                      # 便捷交互启动（docker run 包装）
├── pi-defaults/                # 空配置目录时注入 ~/.pi/agent 的模板
│   ├── AGENTS.md               #   运行期 agent 指令（GitCode 工作流）
│   ├── mcp.json                #   gitcode MCP server（gitcode-api serve）
│   ├── settings.json           #   默认开启 codemode，不设 provider/model
│   ├── skills/gitcode-api/     #   来自 GitCode-API 仓库的 skill
│   └── extensions/gitcode/     #   原生 GitCode 工具扩展
│       ├── api.ts              #     gitcode-api CLI 封装（无 Pi 依赖，可独立测试）
│       ├── index.ts            #     defineTool 注册工具 + /gitcode 命令
│       └── selftest.ts         #     不依赖 LLM 的自测
├── scripts/
│   ├── smoke.sh                # 无凭据自检（当前 23 项）
│   └── verify.sh               # 端到端 fork/push/PR 验证
├── secrets/                    # 本地密钥，gitignore + dockerignore，绝不入镜像
└── workspace/                  # 使用者的仓库检出（非本项目产物）
```

---

## 4. 关键设计决策与「坑」

1. **基镜像与 uid**：`node:24` 自带 `node`(uid/gid 1000)。为与宿主挂载目录的 uid 对齐，
   构建时将其改名为 `agent`（`groupmod -n agent node` + `usermod -l agent … -m node`），
   **不要**再新建 uid 1000 的用户（会冲突）。
2. **Python 环境用 venv**：Debian 是 externally-managed。用 `python3 -m venv /opt/venv`
   安装 `gitcode-api[mcp]` 与 `uv`；不要系统级 `pip install`。
3. **登录 shell 会重置 PATH**：`/etc/profile` 覆盖 `PATH`，`bash -l` 下会丢掉
   `/opt/venv/bin`。故镜像内加 `/etc/profile.d/00-agent-venv.sh` 重新前置 venv
   （非登录 shell 由镜像 `ENV PATH` 覆盖）。
4. **PID 1 用 tini**：`ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]`，
   避免僵尸进程并正确转发信号（agent 会频繁派生 git 子进程）。
5. **命名卷 `.ssh` 归属**：Docker 初始化**空命名卷为 root**，uid 1000 无法写入。
   镜像内预建 `install -d -m 700 -o agent -g agent /home/agent/.ssh`，空卷初始化时即继承
   agent 归属；同时 entrypoint 对 `chmod`/`mkdir`/`ssh-keygen` 失败**容忍并告警**，不中止。
6. **配置注入幂等**：`/opt/pi-defaults` → `~/.pi/agent` 时**仅当目标不存在**才复制，
   挂载的用户配置永远优先；对不可写挂载只告警不失败。
7. **凭据永不入镜像**：`GITCODE_ACCESS_TOKEN`、provider key 走环境变量/挂载；
   SSH 私钥在容器内生成并存于卷；`secrets/` 同时在 `.gitignore` 与 `.dockerignore` 中。
8. **扩展分层以便测试**：`api.ts` **不 import 任何 Pi 包**，因此可用纯 Node 跑
   （Node 24 原生支持 TS 类型剥离）；`index.ts` 才依赖 `defineTool`/`Type`。
   这是「无 LLM 也能验证」的关键。
9. **用户扩展可解析全局 Pi 包**：pi 用 jiti 加载扩展，`@earendil-works/pi-coding-agent`
   与 `typebox` 可解析，**无需**自带 `node_modules`。
10. **`pulls create` 用专用 flag**：`--title/--head/--base` 是必填 flag，
    `--set` 仅用于「没有对应 flag 的可选参数」。`head` 跨 fork 时为 `owner:branch`。
11. **PR 需共同祖先**：分支应从 `upstream/$BASE` 拉出；**空上游仓**（无任何分支）无法接收 PR
    （缺 base 分支），需先 seed 一个 base 分支。
12. **无 LLM 验证扩展加载**：`pi --mode rpc` 发送 `{"type":"get_commands"}`，
    输出含 `"name":"gitcode"` 即表示扩展工厂完整执行（工具注册成功）。

---

## 5. 构建与运行

```bash
# 构建（在 work/ 目录）
docker build -t hiascend-agent-shell:latest .

# 交互运行
./run.sh                 # 进 bash
./run.sh pi              # 直接进 Pi TUI
./run.sh pi -p "…"       # 一次性提示
```

挂载：`/home/agent/.ssh`（卷，SSH 身份）、`/home/agent/.pi/agent`（Pi 配置）、`/workspace`（代码）。
环境：`GITCODE_ACCESS_TOKEN`、`<PROVIDER>_API_KEY`、`GIT_AUTHOR_NAME/EMAIL`、`AGENT_SHELL_QUIET`。

> **开发沙箱**：本项目的开发环境是仓库根目录下的 QEMU Ubuntu 虚拟机
> （见仓库根 `README.md` / `Makefile`）；宿主 `./work` 通过 9p 共享到 guest 的 `/work`，
> 上述命令都在 guest 内执行。

---

## 6. 验证

| 级别 | 命令 | 依赖 | 说明 |
|---|---|---|---|
| Smoke | `bash scripts/smoke.sh` | 无凭据 | 构建 + 工具链 + entrypoint 首启行为 + 扩展加载，当前 **23/23** |
| 扩展自测 | `node ~/.pi/agent/extensions/gitcode/selftest.ts` | token | 走工具同一代码路径，输出 `SELFTEST_OK` |
| 扩展加载 | `pi --mode rpc` + `get_commands` | 无 | 输出含 `"name":"gitcode"` |
| E2E | `SANDBOX_OWNER=<o> SANDBOX_REPO=<r> BASE_BRANCH=<b> bash scripts/verify.sh` | token + SSH | fork→clone→分支→commit→push→PR→校验；**会产生真实副作用** |

新增/修改功能时：**先扩展 `smoke.sh` 的断言**，必要时更新 `selftest.ts`。

---

## 7. 协作约定

- **新增一个 GitCode 工具**：
  1) 在 `pi-defaults/extensions/gitcode/api.ts` 加封装函数（保持无 Pi 依赖）；
  2) 在 `index.ts` 用 `defineTool` 注册，命名 `gitcode_*`，补 `description` 与必要的
     `promptGuidelines`；
  3) 更新 `pi-defaults/AGENTS.md` 的工具清单与 `README.md` 的工具表；
  4) 需要时扩展 `selftest.ts` / `smoke.sh`。
- **新增 skill**：把含 `SKILL.md` 的目录放进 `pi-defaults/skills/`（entrypoint 会注入）。
- **新增 MCP server**：写进 `pi-defaults/mcp.json`，或在扩展里 `pi.registerMcpServer()`。
- **文档边界**：`README.md` 面向使用者，**不要**写开发/测试环境相关内容；
  `AGENTS.md`（本文件）面向开发者；过程记录写 `../NOTES.md`。
- **密钥**：只放 `secrets/`（已被 git/docker ignore）；任何日志/输出都不得回显 token。
- **保持 entrypoint 幂等且容错**：重复启动、只读挂载、缺失可选配置都不能让它失败。
- **提交前自检**：`bash scripts/smoke.sh` 必须全绿。

---

## 8. 快速索引

| 想做的事 | 去处 |
|---|---|
| 改镜像构成 / 依赖 / 用户 | `Dockerfile` |
| 改首启行为（SSH/git/Pi 配置注入） | `entrypoint.sh` |
| 加/改 GitCode 原生工具 | `pi-defaults/extensions/gitcode/{api,index}.ts` |
| 改运行期 agent 指令 | `pi-defaults/AGENTS.md` |
| 改默认 Pi 设置 / MCP | `pi-defaults/settings.json`、`pi-defaults/mcp.json` |
| 加测试 | `scripts/smoke.sh`、`extensions/gitcode/selftest.ts` |
| 使用者文档 | `README.md` |
| 阶段记录 / 决策日志 | `../NOTES.md` |
