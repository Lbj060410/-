# Code Map (功能改动入口)

本文件用于回答两个问题：
1. 这个项目每块代码做什么。
2. 新增/修改某个功能时，要改哪些文件。

## 1) 分层结构

- `pages/`：页面 UI 与页面级协调器。
- `services/`：网络、协议、摄像头、识别、媒体等服务。
- `state/`：跨页面共享状态。
- `config/`：静态配置。
- `entryability/`：HarmonyOS 应用入口生命周期。

## 2) 常见功能改动入口

### 路径规划（黑线最短路径）
- 主要改：`pages/page1/app/PathPlannerAStar.ets`
- 联动改：`pages/page1/app/Page1Coordinator.ets`
- 说明：
  - 修改节点/边（黑线路网）在 `PathPlannerAStar.ets`。
  - 修改触发规划、重规划、执行策略在 `Page1Coordinator.ets`。

### 自动行驶指令（转向/前进/停车/节拍）
- 主要改：`pages/page1/app/Page1Coordinator.ets`
- 联动改：`services/control/CarProtocolService.ets`
- 说明：
  - 执行时机、间隔、状态机在 Coordinator。
  - 新增底层控制码（如 0x0A/0x0B 子命令）在 ProtocolService。

### 到站前停车与超声波分支（p1=0x01/0x02）
- 主要改：`pages/page1/app/Page1Coordinator.ets`
- 联动改：`services/control/CarProtocolService.ets`
- 说明：
  - 到达前转向对齐、发 `ultrasonic()`、等待 0.5s、按 p1 分支重规划在 Coordinator。
  - 若协议格式变更，再改 `pages/page1/net/*` 的解码。

### 收到主车目标点并应用
- 主要改：`pages/page1/app/Page1Coordinator.ets`（`logFrame55` / `scheduleFrameDestApply`）
- 联动改：`pages/page1/net/CarRx55StreamDecoder.ets`

### Page 顶层切页结构（第1/2/3/4页）
- 主要改：`pages/Index.ets`
- 各页实现：`pages/page1/*`、`pages/page2/*`、`pages/page3/*`、`pages/page4/*`

### Page2 视频与云台控制
- 主要改：`pages/page2/Page2View.ets`、`pages/page2/Page2Coordinator.ets`
- 云台改：`pages/page2/components/PtzControlPanel.ets`、`services/control/CameraPtzService.ets`
- 视频源改：`services/source/*`、`services/camera/*`

### 识别引擎与识别调度
- 入口：`services/recognition/RecognitionCenter.ets`
- 工厂与调度：`RecognitionFactory.ets`、`RecognitionScheduler.ets`、`RecognitionLoop.ets`
- 模型后端：`NcnnRecognitionService.ets`（离线）与 `HttpYoloRecognitionService.ets`（网络）
- 状态展示：`state/RecogStore.ets` + 页面显示模块

### TCP 连接与收发
- 主要改：`services/control/CarTcpService.ets`
- 协议封包：`services/control/CarFrameCodec.ets`
- 指令 API：`services/control/CarProtocolService.ets`

## 3) 修改前建议

- 先定位“功能入口文件”（上表）。
- 再搜调用链：
  - `rg -n "函数名|字段名" entry/src/main/ets`
- 最后再改 UI 显示层与状态层，避免只改页面不改逻辑。

## 4) 注释约定

所有 `.ets/.ts` 文件顶部已加入 `CODE GUIDE` 注释，包含：
- `Purpose`：文件功能。
- `Change here when`：什么需求改这里。
- `Related`：相关联文件。

后续新增文件时，建议复制同样格式，保证可维护性。

## 5) 变量调参说明

- 变量含义与“调大/调小影响”见：
  - `VARIABLE_GUIDE.md`

