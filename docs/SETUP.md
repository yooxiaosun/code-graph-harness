# Harness 环境准备（Setup）

> 本文档是 Code Graph · 知识抽取 Harness 的运行环境依赖清单与安装指引。
> 目标环境：Linux（含 WSL）/ macOS。**Win10 需先安装 WSL** 再按 Linux 指引安装。

## 1. 依赖清单

| 工具 | 用途 | 必需 | 缺失影响 | 内网获取方式 |
|------|------|:---:|---------|:---:|
| `git` | 克隆/更新仓库（Phase 1） | ✅ | 无法获取仓库 | 内网 git 服务 |
| `bash` | 全部脚本解释器 | ✅ | 工程不可运行 | 系统自带 |
| `jq` | JSON 处理（Phase 2-4、门禁） | ✅ | 13 个脚本 ABORT | **项目实例自带 `project/tools/jq`（§2.6）** |
| `node` | JSON 解析、extractors、opencode | ✅ | pipeline Phase 0 硬检查失败 | npm 代理镜像 |
| `python3` | YAML 解析（run-ai-analysis / GE2.5） | ✅ | AI 迭代分析驱动失效 | 系统包 / 离线 |
| `curl` | nightly 模式 Ollama 调用 | ⚠️ 仅 nightly --ai | AI 归因功能不可用 | 系统自带 |

> **内网 npm 代理镜像**（环境速查，非工程硬依赖）：node 生态可通过内网 npm registry 安装。
> 工程本身运行时**不需要任何 npm 包**（JSON 处理用 jq，YAML 用 python3），npm 镜像仅用于
> opencode 等外部工具或未来 node 兜底方案。

## 2. 安装指引

### 2.1 Linux / WSL (Debian/Ubuntu) — 在线

```bash
sudo apt-get update
sudo apt-get install -y git bash jq nodejs python3 curl
```

验证：

```bash
git --version && bash --version | head -1 && jq --version && node --version && python3 --version
```

### 2.2 Linux (RHEL/CentOS)

```bash
sudo yum install -y git bash jq nodejs python3 curl
```

### 2.3 Linux (Fedora)

```bash
sudo dnf install -y git bash jq nodejs python3 curl
```

### 2.4 macOS（可选开发环境）

```bash
brew install jq node python3 curl
# git/bash 系统自带
```

### 2.5 Win10 → WSL（若尚未安装）

```powershell
# PowerShell (管理员)
wsl --install
# 重启后按提示设置 Ubuntu 用户名/密码
# 进入 WSL 后按 §2.1 或 §2.6 安装依赖
```

### 2.6 离线安装 jq（内网无外网）

> **md-first（D12）**：harness 不写自动引导胶水，只在 md 声明"环境需 jq"。
> 项目实例自带 `project/tools/jq` **Linux x86-64 静态二进制**（v1.7.1，单文件，零依赖），
> 由 AI 或运维按需安装到系统 PATH。

**用法一（项目自带二进制，全局安装）**：

```bash
# 从项目实例把 jq 拷到系统 PATH
sudo install -m 755 /Users/johnsmith/WorkBench/code-graph/project/tools/jq /usr/local/bin/jq
jq --version      # jq-1.7.1
```

**用法二（从外网下载覆盖/升级）**：在内网有外网通道的机器下载官方静态二进制，覆盖 `project/tools/jq`：

```bash
# 确认架构
uname -m                       # x86_64 → jq-linux-amd64; aarch64 → jq-linux-arm64

# x86_64（绝大多数 WSL）：
wget -O /Users/johnsmith/WorkBench/code-graph/project/tools/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
# ARM64（M 芯片 Mac 上的 WSL）：
wget -O /Users/johnsmith/WorkBench/code-graph/project/tools/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64
chmod +x /Users/johnsmith/WorkBench/code-graph/project/tools/jq
```

> **说明**：`project/tools/jq` 是 Linux x86-64 静态二进制，仅用于内网 WSL/Linux 运行时。
> macOS 开发机请用系统自带 jq（`brew install jq`）。环境要求由 `pipeline.sh` Phase 0
> 检查，缺失时打印安装命令并指向本 §2.6。

## 3. 验证清单

安装后运行：

```bash
# 1. 全量语法检查（应无输出）
find scripts .harness -name '*.sh' -exec bash -n {} \;

# 2. 配置校验（应 OK, 0 warning）
bash scripts/validate-config.sh

# 3. 测试套件（应 0 失败）
bash scripts/tests/run.sh

# 4. 管道冒烟（应 exit 0）
bash scripts/pipeline.sh
```

`pipeline.sh` Phase 0 会自动检查 git/bash/jq/node，缺失时打印精确安装命令。

## 4. 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `[FAIL] 关键依赖缺失: jq` | jq 未装到系统 PATH | 见 §2.6（用 project/tools/jq 或下载） |
| `[JQ-BOOTSTRAP] 系统无 jq, 已启用工程自带 tools/jq` | 系统无 jq，bootstrap 自动注入 tools/jq | 正常提示，无需处理 |
| nightly 状态不更新 | 旧版脚本用 macOS `sed -i ''` | 拉取最新代码（已修复为 GNU `sed -i`） |
| `python3: command not found` | python3 未装 | `sudo apt-get install -y python3` |
| 文件行尾错乱 | 未用 LF 行尾 | `.gitattributes` 已强制 `eol=lf`，重新 clone 即可 |

## 5. 跨平台说明（v2.3）

- 工程脚本按 **Linux/WSL（GNU coreutils）** 编写：`sed -i`、`stat -c %Y`
- 仍保留少量 BSD/macOS 兜底（`json-writer.sh` sed 双写、`nightly.sh` stat 双写），macOS 开发可用
- **jq 来源策略（v2.3）**：
  - macOS 开发机：系统 jq（`brew install jq`）
  - 内网 WSL/Linux：工程自带 `tools/jq`（静态二进制，`jq-bootstrap.sh` 自动发现）
  - 优先级：系统 jq > 工程 tools/jq（bootstrap 尊重系统环境）
- 无需 jq 之外的任何 JSON 专用工具（node 可全量替代）
