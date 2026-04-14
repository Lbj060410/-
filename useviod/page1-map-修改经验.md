# Page1 地图改造经验记录

## 1. 架构层面
- 地图底图改成纯代码绘制后，建议把样式参数集中在一个配置对象（如 `PARKING_MAP_STYLE`），避免魔法数字散落。
- 路网拓扑、节点坐标、UI 绘制要分层：  
`PathPlannerAStar` 管“怎么走”，`SandboxGridTypes` 管“点在哪里”，`SandboxMap` 只管“怎么画”。

## 2. ArkTS/UI 语法坑
- `@Builder` 中避免局部 `const/let`，容易触发 `does not comply with the UI component syntax`。
- `@Builder` 中不要做状态写入或复杂副作用（如日志写状态），放到普通方法里。
- `ForEach` 必须给稳定 key，避免渲染异常或白屏。

## 3. 路线提示线（tishixian）经验
- 先确认“数据链路”再看“显示链路”：
  - 数据是否变：目标、路径节点、重规划结果是否更新。
  - 显示是否变：最终用于绘制的 rect 数量、可视区数量是否大于 0。
- 本次日志证明过：`nodes/rects/screenVisible` 都正常时，问题通常是图层覆盖，而不是算法失败。
- 图层顺序固定后更稳定：
  - 地图底层
  - 路线层
  - 点位/障碍/目的地标志
  - 小车相关最上层

## 4. 交互规则经验
- “目标二次确认”场景下，路线显示规则要明确：
  - 未确认新目标：继续显示旧路线。
  - 确认后触发重规划：旧路线消失，新路线出现。
- 规则不要混杂在多个分支，建议统一在一个函数（如 `activeHighlightNodes()`）集中判定。

## 5. 资源替换经验（白块贴图）
- 白块图片替换建议采用“行列映射”函数（`rowIndex + blockIndex -> rawfile`），便于批量替换。
- 图片路径务必用实际资源路径：`$rawfile('map/xxx.jpg')`。
- 图片块要 `clip(true)` + `ImageFit.Cover`，同时保留原边框样式，视觉更统一。

## 6. 调试建议（可长期保留）
- 保留 `tishixian` 标签日志，但要做去重，避免刷屏。
- 推荐日志字段：
  - `source`（当前用的是 pending/path/none）
  - `nodes`（首尾与数量）
  - `rects`（绘制段数量）
  - `screenVisible`（屏幕可见段数量）
  - `zoom/offset/mapW/mapH`

