# Harness 环境准备（Setup）

> 本文档是 Code Graph · 知识抽取 Harness 的运行环境依赖清单与安装指引。
> 目标环境：Linux（含 WSL）/ macOS。**Win10 需先安装 WSL** 再按 Linux 指引安装。

## 1. 依赖清单

| 工具 | 用途 | 必需 | 缺失影响 |
|------|------|:---:|---------|
| `git` | 克隆/更新仓库（Phase 1） | ✅ | 无法获取仓库 |
| `bash` | 全部脚本解释器 | ✅ | 工程不可运行 |
| `jq` | JSON 处理（Phase 2-4、门禁） | ✅ | validate-schema/GE3/compute-stats 等 13 个脚本 ABORT |
| `node` | JSON 解析、extractors、opencode | ✅ | pipeline Phase 0 硬检查失败；extractors 异常 |
| `python3` | YAML 解析（run-ai-analysis / GE2.5） | ✅ | AI 迭代分析驱动失效 |
| `curl` | nightly 模式 Ollama 调用 | ⚠️ 仅 nightly --ai | AI 归因功能不可用 |

## 2. 安装指引

### 2.1 Linux / WSL (Debian/Ubuntu)

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
# 进入 WSL 后按 §2.1 安装依赖
```

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
| `[FAIL] 关键依赖缺失: jq` | jq 未装 | `sudo apt-get install -y jq` |
| nightly 状态不更新 | 旧版脚本用 macOS `sed -i ''` | 拉取最新代码（已修复为 GNU `sed -i`） |
| `python3: command not found` | python3 未装 | `sudo apt-get install -y python3` |
| 文件行尾错乱 | 未用 LF 行尾 | `.gitattributes` 已强制 `eol=lf`，重新 clone 即可 |

## 5. 跨平台说明（v2.3）

- 工程脚本按 **Linux/WSL（GNU coreutils）** 编写：`sed -i`、`stat -c %Y`
- 仍保留少量 BSD/macOS 兜底（`json-writer.sh` sed 双写、`nightly.sh` stat 双写），macOS 开发可用
- 无需 jq 之外的任何 JSON 专用工具（node 可全量替代）
