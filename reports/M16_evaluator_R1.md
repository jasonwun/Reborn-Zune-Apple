# M16 验收报告 — 瓷砖墙性能专项

日期：2026-09-27 ｜ 实现：M16 三项修复 ｜ 依据：`specs/M16.md`、基线 `reports/M16_baseline.md`
测量方法同基线：demo 库 + `REBORN_ZUNE_DEBUG_INITIAL_ROUTE=nowPlaying`，静置 25 s，`top -l 10` + `footprint`。

## Acceptance 核对

| # | 标准 | 结果 | 判定 |
| --- | --- | --- | --- |
| 1 | 播放页静置 CPU ≤ 8% | 稳态 5.8–7.2%（基线 22.6%） | **PASS** |
| 2 | footprint 实测记录 | 544 MB（基线 476 MB，基本不变；各次运行 ±15% 波动来自每次启动随机 expansionSeed 的瓷砖数量差异） | PASS（如实记录：节帧省时间不省驻留，见下） |
| 3 | 视觉零回归 | 静态快照路径（`staticSnapshot`）未触碰，M5 快照测试全绿；光照移动/翻牌/入场动画逻辑参数均未改，仅采样率降为 15 fps | PASS（逻辑层面）；实机目检待用户确认 |
| 4 | `swift test` 全绿 | 127/127 通过（含新增 12 项 M16 测试） | **PASS** |
| 5 | resize 不整墙重放动画 | 单元测试覆盖：格界内 resize 命中缓存、id 前缀在面板增长后保持稳定（`testExpandedPrefixSurvivesPanelGrowth`） | PASS（测试层面）；实机拖拽目检待用户确认 |

## 改动清单

1. `Sources/RebornZuneCore/Views/LightingModifier.swift` —
   `TimelineView(.animation)` → `.animation(minimumInterval: 1/15)`，
   `frameInterval` 暴露为 `static let`。
2. `Sources/RebornZuneCore/Views/TileWallView.swift` —
   扩展瓷砖 id 改为 (seed, index) 确定性派生（`expansionID`，
   SplitMix64 混合）；新增 `TileWallExpansionCache`（@State 持有的
   引用类型 memoizer，key = 格数 × unitSize × seed × 源身份）。
3. `Tests/RebornZuneCoreTests/TileWallExpansionTests.swift` — 新增 12 项。
4. `specs/M16.md`、`reports/M16_baseline.md`、本报告。

## 帧率迭代记录

| 光照帧率 | 稳态空闲 CPU |
| --- | --- |
| 原生 60 Hz（基线） | 22.6% |
| 30 fps | ~13% |
| 20 fps | ~9% |
| **15 fps（采用）** | **~6–7%** |

## 已知残留（后续里程碑候选）

- **翻牌脉冲尖峰**：每 5 s 一次翻牌，单块瓷砖 1.8 s 动画期间整面墙的
  colorEffect 层按 vsync 全帧重渲染，CPU 冲到 ~17–19%。要根治需改
  架构（如光照只作用于静态快照层、翻牌瓷砖叠加在上层），有视觉风险，
  本里程碑不动。
- **内存驻留 ~480–540 MB**：`colorEffect` 启用期间离屏纹理与瓷砖图像
  的 GPU 拷贝常驻，与帧率无关。候选方向：把 `.saturation(0)` 合并进
  Metal shader（省一次全屏 pass 和一张中间纹理），或降低光照层采样
  分辨率。需视觉对照验证，另立里程碑。
