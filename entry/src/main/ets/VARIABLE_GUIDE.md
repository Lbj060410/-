# VARIABLE_GUIDE（变量含义与调参影响）

本文件只关注“改变量会怎样”。

## 1. `pages/page1/app/Page1Coordinator.ets`

| 变量 | 默认值 | 含义 | 改大会怎样 | 改小会怎样 |
|---|---:|---|---|---|
| `PAUSE_REPLAN_MS` | `350` | 重规划后暂停窗口 | 更稳，减少抖动重规划 | 更灵敏，但可能频繁 STOP/PLAN |
| `REPLAN_COOLDOWN_MS` | `700` | 重规划冷却时间 | 重规划次数更少 | 反应更快但更容易重复规划 |
| `YOLO_COOLDOWN_MS` | `1200` | 识别触发障碍注入冷却 | 误检影响更小 | 对识别更敏感，误触概率上升 |
| `FRAME_DEST_APPLY_DELAY_MS` | `2000` | 主车目标延迟应用 | 抗抖更强，目标生效慢 | 切换更快，可能抖动 |
| `PARK_STEP_DELAY_MS` | `2000` | 转向后进入泊车前等待 | 车头更易对齐，但更慢 | 更快，但对齐不足风险增加 |
| `ULTRASONIC_WAIT_MS` | `500` | 超声波返回等待窗口 | 更容易等到返回帧 | 更容易超时直接走旧流程 |
| `SIM_TICK_MS` | `100` | 主循环 tick 间隔 | CPU更省，动画更粗 | 更平滑，CPU开销更高 |
| `STEP_TRAVEL_MS` | `1500` | 单段模拟行驶时长 | 显示速度变慢 | 显示速度变快 |
| `COMMAND_INTERVAL_MS` | `4000` | 指令节流间隔 | 动作更稳但慢 | 快但易叠命令 |
| `VISION_LOG_COOLDOWN_MS` | `1200` | 识别日志节流 | 日志更干净 | 日志更详细但可能刷屏 |
| `lastUltrasonicP1` | `-1` | 最近超声波结果（`0x01/0x02`） | N/A（状态变量） | N/A |
| `logicalHeadingDeg` | `0` | 逻辑朝向，决定先转向还是直行 | N/A（状态变量） | N/A |

## 2. `pages/page1/app/Page1UiStore.ets`

| 变量 | 默认值 | 含义 | 改大会怎样 | 改小会怎样 |
|---|---:|---|---|---|
| `gridSnapThresholdNorm` | `0.055` | 节点吸附阈值 | 更容易吸附节点 | 更难吸附，需更精准点选 |
| `edgeSnapBoostNorm` | `0.010` | 边缘节点额外吸附增益 | 边缘点更易命中 | 边缘点命中难度接近普通点 |
| `edgePickThresholdNorm` | `0.030` | 点击选中路段阈值 | 更易选中路段 | 误触少但更难选中 |
| `obstaclePointPickThresholdNorm` | `0.030` | 新增点障碍阈值 | 更容易新增点障碍 | 更难新增 |
| `obstaclePointRemoveThresholdNorm` | `0.020` | 删除点障碍阈值 | 更容易删点 | 更难删点 |
| `obstaclePointTriggerThresholdNorm` | `0.022` | 点障碍命中阈值 | 更容易触发避障 | 更不易触发 |
| `autoAvoidCooldownMs` | `1200` | 自动避障冷却 | 更稳，不频繁改路径 | 更灵敏，频繁改路径 |
| `autoFollowCooldownMs` | `1500` | 自动跟随动作冷却 | 动作慢但稳 | 动作快但可能叠命令 |
| `segMidMinT` | `0.12` | SEG 中段下界 | 区间缩小（若提高）更保守 | 区间扩大（若降低）更常启用 SEG |
| `segMidMaxT` | `0.88` | SEG 中段上界 | 区间扩大（若提高）更常启用 SEG | 区间缩小（若降低）更保守 |
| `segHeadingPenaltyWeight` | `0.55` | SEG 中朝向惩罚权重 | 更偏向朝向一致路径 | 更偏向纯距离最短 |
| `realSendEnabled` | `true` | 是否允许真实发包 | N/A（布尔） | N/A |
| `riskScore` | 动态 | 风险评分（由传感器算） | N/A（结果变量） | N/A |

## 3. `pages/page1/app/PathPlannerAStar.ets`

| 变量 | 含义 | 修改后果 |
|---|---|---|
| `ROUTE_NODE_IDS` | 可参与规划的节点白名单 | 改了必须同步 `ROUTE_EDGES`，否则出现“节点合法但不可达” |
| `ROUTE_EDGES` | 黑线路网边定义 | 直接决定最短路可走范围；`a/g` 节点不应跨行竖连 |
| `COLS` / `ROW_LABELS` | 节点编码规则 | 改后会影响所有 `A2/D4/G6` 解析逻辑 |

## 4. `services/control/CarProtocolService.ets`

| 变量 | 默认值 | 含义 | 修改后果 |
|---|---:|---|---|
| `mode` | `REAL_SEND` | 发送模式（真实/演练） | 改为 `DRY_RUN` 后所有动作只记日志不发车 |
| `0x0A` 子码 | N/A | 车辆动作码（前进/转向/超声波等） | 子码改错会导致动作映射错误 |
| `packBroadcastPayloads` 分片上限 | `8` 字节 | 文本播报每帧 payload 大小 | 改大将破坏当前 12B 协议约束 |

## 5. `services/control/CarTcpService.ets`

| 变量 | 默认值 | 含义 | 改大会怎样 | 改小会怎样 |
|---|---:|---|---|---|
| `maxReconnect` | `3` | 最大自动重连次数 | 容错更强但等待更久 | 更快失败返回上层 |
| `heartbeatIntervalMs` | `5000` | 心跳间隔 | 开销小但断链发现慢 | 发现快但开销大 |
| `socketTimeout` | `10000` | socket 超时 | 弱网更稳但失败感知慢 | 失败感知快但误超时上升 |
| `connectSeq` | 动态 | 连接代次标识 | 状态变量，不建议手改 | 状态变量，不建议手改 |

## 6. 调参建议（安全顺序）

1. 先改冷却类变量（如 `REPLAN_COOLDOWN_MS`、`autoFollowCooldownMs`）。
2. 再改阈值类变量（如 `gridSnapThresholdNorm`、`obstaclePointTriggerThresholdNorm`）。
3. 最后再改协议/网络层变量（如子命令码、`socketTimeout`）。

原因：冷却类最不容易破坏协议语义，排障成本最低。
