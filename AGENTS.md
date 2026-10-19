# AGENTS.md — hiascend-agent 开发指南

> 面向**本部署包的开发者与接手开发的 agent**。使用者文档见 `README.md`。
> 运行期 agent 的指令在 `config/AGENTS.md`（安装时合并进 `~/.pi/agent/`）。

---

## 1. 目标与现状

- **目标**：为**无外网、root、x86_64 的 openEuler 环境**提供一条命令即可装好的
  算子开发 agent shell：Pi + fd + ripgrep + gitcode-api + skills/prompts。
- **形态**：源码仓库 + GitHub CI 产出的**可重定位 release 包**（不把二进制放进仓库）。
- **现状**：install / 配置合并 / doctor / uninstall 已在 `openeuler/openeuler:24.03-lts`
  **无网容器**中验证通过。

### 为什么不是 Docker 镜像

远程开发环境本身通常是平台给的容器（无 DinD/特权），NPU 驱动与 CANN 绑定宿主；
因此以用户态安装包交付更稳。Docker 仅作为 CI 测试手段。

---

## 2. 仓库结构（只放源码）

```
work/
├── install.sh                 # 安装器（校验/解包/venv/渲染配置/合并/自检）
├── uninstall.sh               # 卸载（可选清理配置）
├── bin/hiascend-agent         # 启动器（PATH/PI 目录/子命令）
├── config/                    # 系统配置层（安装到 <prefix>/<ver>/config）
│   ├── AGENTS.md              #   运行期 agent 指令
│   ├── settings.json.in       #   含 __PREFIX__ 占位符
│   ├── mcp.json.in            #   gitcode MCP server（绝对路径）
│   ├── skills/                #   operator-dev/、gitcode-api/（目录形式）
│   ├── prompts/               #   *.md → /命令（README 用 .txt）
│   └── extensions/gitcode/    #   原生 GitCode 工具扩展
├── lib/
│   ├── merge-config.py        # 系统层 + 用户层合并（仅 stdlib）
│   └── doctor.sh              # 环境/资源自检
├── packaging/
│   ├── versions.env           # 固定版本与 SHA256
│   ├── build-release.sh       # 下载/校验/组装/打包
│   └── test-in-container.sh   # openEuler 无网安装测试
├── .github/workflows/release.yml
├── README.md
└── AGENTS.md
```

**仓库里不提交**：`dist/`、`build/`、`vendor/`、wheels、任何二进制。

---

## 3. 发布包内容与安装流程

```
hiascend-agent-<pkgver>-linux-x86_64/
├── install.sh / uninstall.sh / VERSION / PI_VERSION / versions.env / SHA256SUMS
├── bin/hiascend-agent
├── lib/{merge-config.py,doctor.sh}
├── config/...
└── vendor/
    ├── pi/                    # Pi 1.1.0 standalone（pi/pi + assets）
    ├── bin/{fd,rg}            # musl 静态二进制
    └── wheels/                # gitcode-api[mcp]==1.3.4 + 依赖（cp311 manylinux x86_64）
```

安装：
1. 校验 `SHA256SUMS`；
2. 解包到 `<prefix>/<pkgver>`，建 `current` 软链；
3. `python3.11 -m venv` + `pip install --no-index --find-links vendor/wheels gitcode-api[mcp]`；
4. 渲染 `config/*.in`（`__PREFIX__` → 安装前缀）；
5. `lib/merge-config.py` 合并到 `~/.pi/agent`（用户优先）；
6. 写 `/usr/local/bin/hiascend-agent`；可选生成 SSH key / 设置 git 身份；
7. 运行 doctor。

启动器 `<prefix>/current/bin/hiascend-agent` 设置 `PATH`（`bin` + `venv/bin`）、
`GITCODE_API_BIN`、`PI_CODING_AGENT_DIR`，再 exec Pi。

---

## 4. 关键设计决策

1. **Pi 用官方 standalone 二进制**：环境里 Node/npm 不满足要求、dnf 也没有 pi；
   standalone 直接绕开 Node，固定 1.1.0。
2. **fd / ripgrep 用 musl 静态包**：不受 openEuler glibc 影响。
3. **gitcode-api 完整保留**：离线 wheels（cp311 manylinux x86_64）随包分发；
   无外网也能 `pip install --no-index`。
4. **系统层 + 用户层合并**：`settings.json` 递归合并（用户优先，资源数组取并集）；
   `mcp.json` 的 `mcpServers` 取并集；`AGENTS.md` 用户优先。
5. **绝对路径 + `current` 软链**：skills/prompts/extensions 指向
   `<prefix>/current/...`；升级只切软链，资源立即生效，不复制进用户目录。
6. **`__PREFIX__` 渲染**：`settings.json.in` / `mcp.json.in` 在安装时替换前缀；
   MCP 命令用绝对路径，不依赖 shell PATH。
7. **无网优先**：安装默认不联网；只有 `--fetch` 才通过 `--ghproxy` 下载 Pi/fd/rg，
   且逐个校验 SHA256。wheels 必须随包。
8. **版本化前缀**：`<prefix>/<ver>` + `current`；可并存多个版本。
9. **卸载顺序**：先算剩余版本/更新 `current`/删启动器，**最后**才 `rm -rf` 版本目录
   （脚本可能正在该目录中运行）。
10. **二进制不进仓库**：由 CI 下载并组装；仓库只保留源码与 `versions.env` 的 pin。

---

## 5. 构建与验证

```bash
# 构建 release 包（本机需 python3.11+pip 或 docker；可走 ghproxy）
GHPROXY=https://ghproxy.com/ packaging/build-release.sh

# 在 openEuler 无网容器里安装、doctor、卸载
packaging/test-in-container.sh
```

`packaging/versions.env` 固定：
Pi 1.1.0、fd 10.5.0、ripgrep 15.2.0、gitcode-api 1.3.4。

CI（`.github/workflows/release.yml`，tag `v*`）：
build → 无网容器测试 → 上传 artifact → 创建 GitHub Release。

### 已踩过的坑

- **9p/共享目录不允许 chown**：解包/复制用 `tar --no-same-owner`、
  `cp -a --no-preserve=ownership`。
- **openEuler 的 `sort` 不支持 `-V`**：脚本里只用可移植选项。
- **不要在被执行脚本所在目录里 `rm -rf` 它**：卸载时把删除放到最后。
- **`prompts/` 下所有直接 `.md` 都会变成命令**：说明文件用 `.txt`。
- **skill 必须是 `<name>/SKILL.md` 且有 `name` + `description`**，否则 Pi 不加载。
- **登录 shell 会重置 PATH**：启动器显式设置 PATH；不要依赖交互 shell 的环境。

---

## 6. 协作约定

- **新增 skill**：`config/skills/<name>/SKILL.md`（目录形式），frontmatter 含
  `name`/`description`；细则放 `references/`。改完在 `test-in-container.sh` 或
  doctor 里断言 `skill:<name>` 被发现。
- **新增提示词模板**：`config/prompts/<name>.md`；文件名即命令名；说明文件用 `.txt`。
- **新增二进制**：只改 `packaging/versions.env` + `build-release.sh`，不要提交二进制。
- **改合并语义**：只改 `lib/merge-config.py`，并补 `test-in-container.sh` 的断言。
- **保持离线**：安装路径不得依赖网络；新增依赖必须进入 `vendor/`。
- **文档边界**：`README.md` 面向使用者；本文件面向开发者。

---

## 7. 快速索引

| 想做的事 | 去处 |
|---|---|
| 改安装/升级/卸载行为 | `install.sh`、`uninstall.sh` |
| 改启动器/PATH/子命令 | `bin/hiascend-agent` |
| 改系统与用户配置合并 | `lib/merge-config.py` |
| 改自检项 | `lib/doctor.sh` |
| 改 skill / prompt | `config/skills/`、`config/prompts/` |
| 改 GitCode 原生工具 | `config/extensions/gitcode/` |
| 改固定版本/SHA | `packaging/versions.env` |
| 改打包流程 | `packaging/build-release.sh` |
| 改 CI | `.github/workflows/release.yml` |
| 面向用户的说明 | `README.md` |
