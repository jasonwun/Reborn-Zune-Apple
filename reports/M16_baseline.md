# M16 性能基线 — 瓷砖墙专项

日期：2026-09-27 ｜ 构建：Debug (HEAD 964d322, M15.1) ｜ 机器：本机 macOS（Apple Silicon，Retina 2x）
方法：`REBORN_ZUNE_DEBUG_DEMO_LIBRARY=1` + `REBORN_ZUNE_DEBUG_INITIAL_ROUTE=nowPlaying` 直接进播放页，静置 8 s 后用 `top -l 3`（取末次采样）与 `/usr/bin/footprint` 测量。

## 核心数据

| 配置 | Footprint | 空闲 CPU |
|---|---|---|
| 播放页，光照开（现状） | **476 MB**（264 MB 未映射显存 + 134 MB IOSurface） | **22.6%**（持续） |
| 播放页，光照关（`REBORN_ZUNE_DEBUG_NO_LIGHTING=1`） | **58 MB** | **≈0%** |
| 差值（光照效果的全部成本） | **≈418 MB** | **≈22.6%** |

结论：**瓷砖墙的全部空闲性能成本都来自光照效果**（`LightingModifier` 的 `TimelineView(.animation)` + 全屏 `colorEffect`）。翻转调度（1 次/5 s）与瓷砖本身在光照关闭时几乎零成本。

## 代码审查确认的三个热点

1. **`LightingModifier` 每帧驱动全屏 Metal shader**（`Sources/RebornZuneCore/Views/LightingModifier.swift:23`）。
   `TimelineView(.animation)` 按屏幕刷新率（最高 120 Hz）tick，每帧重建 shader 并对整面墙重新应用 `colorEffect`。整面子树被迫离屏光栅化成纹理供 shader 采样——这是 264 MB 显存 + 134 MB IOSurface 的来源。而光周期是 **120 秒**，肉眼根本分辨不出 60 fps 和 30 fps 的差别。
2. **扩展瓷砖的 id 每次 body 求值都重新随机**（`TileWallView.swift:11, 73, 146`）。
   `expanded()` 在 body 内调用，合成 entry 用默认 `id: UUID()`。而 body 会被两类事件频繁触发：① `flipCoordinator.flipPulses` 每 5 s 变化一次（`tileLayout` 读取它，注册了 @Observable 依赖）；② 拖拽改窗口大小时 `GeometryReader` 连续失效。每次触发 → 全部扩展瓷砖身份失效 → 整面墙销毁重建（含入场动画重放）。
3. **`expanded()` 结果无缓存**（`TileWallView.swift:73`）。
   窗口尺寸每变 1 pt 就重跑一次扩展采样（129→678 块的 RNG 采样 + 数组构建）。应只在大致格数变化时重算。

## 次要观察（非瓷砖墙）

- 演示库下 58 MB 的基础 footprint 健康；合成平色图（256×256）未造成明显压力。
- 启动耗时与 Time Profiler 采样本轮未测（前次被用户打断）；瓷砖墙结论已足够明确，优先级让位。

## M16 建议范围（待用户确认）

1. 光照动画降帧：`TimelineView(.animation)` → 约 30 fps 的节流 schedule（窗口被遮挡时暂停更佳）。
2. 扩展瓷砖 id 稳定化：以 (seed, index) 派生确定性 id。
3. `expanded()` 缓存：按（面板格数 bucket, unitSize, seed）做 key。
4. 验收标准：播放页空闲 CPU ≤ 8%、footprint 降幅可测、视觉上光照/翻转/入场动画与现状一致（M5 系列快照测试须保持全绿）。
