# Code Graph Harness — Quality Contract

- Project: Code Graph Harness
- Stack: shell
- Agent: Claude Code / OpenCode

## Source Of Truth
- agentEntry: `HARNESS.md`
- workflowState: `docs/status/state.yaml`
- runtimeCommands: `.agent/project.json`
- qualityContract: `harness-conf/workflow/gate-criteria.md`
- relatedStandards: `docs/standards/ENGINEERING_RULES.md`

## Task Levels
| Level | Intent | Required Artifacts | Required Verification |
| --- | --- | --- | --- |
| S | 单点小改、文案、配置调整 | — | `bash scripts/tests/run.sh` |
| M | 功能增强、bugfix、提取器修改 | extraction report | `bash scripts/tests/run.sh`, `bash scripts/validate-config.sh` |
| L | 新增提取器、架构变更 | plan.md, report, GP1-GP5 verification | full gate run |
| CRITICAL | 管道核心变更、图谱 schema 修改 | plan.md, review, full gate run | `bash scripts/gates/all.sh`（默认集 G0/G4/G5）+ `bash scripts/tests/run.sh` |

## Verification Profiles
| Profile | Required | Success Rule |
| --- | --- | --- |
| fast | `bash -n scripts/**/*.sh`, `bash scripts/tests/run.sh` | 语法检查 + 基本测试通过 |
| default | fast + `bash scripts/validate-config.sh` | 配置验证通过 |
| release | default + `bash scripts/pipeline.sh` | 全流程跑通，图谱产物生成 |

## Red Lines
- 不得声称未运行的验证通过
- 提取器脚本必须先过 GP1-GP5 fixture 验证再集成
- 自适应迭代上限 3 次，超限必须升级 User 决策
- 发布确认是硬停闸，必须 User 确认后归档
- 不得在日志、文档中输出 token、密码、密钥和连接串
