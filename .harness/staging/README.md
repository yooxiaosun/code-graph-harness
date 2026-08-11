# .harness/staging/ · E4 交付包暂存区（AI 唯一可写区）

> **定位**：E4 自适应编码的 AI 产物**唯一**落地位置。`adapter-developer` 的 edit 权限收束于此，
> 正式目录 `scripts/extractors/` 只能通过晋级闸门 `scripts/promote-extractor.sh` 写入。
> 规则：`harness-conf/workflow/nightly-mode.md §7 三道防线`。

## 目录约定

```
.harness/staging/
├── README.md                    # 本规范
├── archived/                    # 已晋级交付包归档（promote 自动移入，只增不改）
└── <pattern>/                   # 一个未知模式 = 一个交付包
    ├── extract-<pattern>.sh     # 提取器本体（bash + set -euo pipefail）
    ├── E4-REPORT.md             # 模式分析结论 / 自证命令与输出 / 建议集成点
    └── fixtures/
        ├── sample-<pattern>/    # 触发该模式的样例仓库（Java 代码）
        └── expected/<pattern>.json  # 期望输出（InterfaceNode 数组）
```

## 交付包准入要求

1. **三件套齐全**：`extract-<pattern>.sh` + `fixtures/sample-<pattern>/` + `fixtures/expected/<pattern>.json`，缺一不可
2. **脚本规范**：`#!/usr/bin/env bash` + `set -euo pipefail`；参数 `<service-name> <repo-path> [output-dir]`；source `../base/java-parser.sh` 与 `../base/json-writer.sh`；输出 `nonstandard-<pattern>.json`
3. **自证全绿**：`bash scripts/e4-verify-bundle.sh <pattern>` 必须 exit 0（GP1 语法 / GP2 执行 / GP3 JSON / GP4 召回 / GP5 回归）
4. **模式命名**：小写 kebab-case（如 `redis-client`）；不得与既有非标提取器重名（http-client/mq/custom-socket）

## 生命周期

```
E4 产出 → 自证全绿 → 标记"待晋级"（晨检队列/交互确认）
         → bash scripts/promote-extractor.sh <pattern>   # 唯一晋级通道
         → 晋级成功 → 交付包移入 archived/<pattern>-<YYYY-MM-DD>/
```

- 夜间 `--e4` 默认只标记待晋级，不自动晋级
- 失败交付包**保留**在 staging 供次日人工诊断，不自动删除

## 禁止

- 任何人/AI 不得在 staging 外绕过晋级闸门直接修改 `scripts/extractors/**`
- 不得将 `repos.yaml`、`harness-conf/**`、`output/**` 产物放入 staging（staging 只放提取器交付包）
- 不得用 staging 目录做版本库/存档用途（版本由 git 管理，此处只存待晋级产物）
