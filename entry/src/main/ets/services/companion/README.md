# Tablet Companion MVP (HarmonyOS)

本目录提供“平板伴侣代理”最小模板，用于打通：

`page4 -> OpenClaw 网关 -> /v1/tablet/* -> 平板伴侣代理`

## 文件

- `TabletCompanionContract.ets`：请求/响应协议
- `TabletCompanionService.ets`：动作处理器（set_alarm/open_app/list_alarm）
- `TabletCompanionHttpExample.ets`：HTTP 路由挂载示例

## 当前状态

- `set_alarm`：已调用 `startAbility` 拉起时钟应用（并携带 hour/minute/label 参数）
- `open_app`：已调用 `startAbility` 拉起目标应用
- `list_alarm`：返回伴侣服务内存中的闹钟记录

说明：
- 不同 HarmonyOS 机型/时钟应用对参数键支持不一致，可能出现“拉起了时钟，但未自动填入时间”。
- 这是平台兼容问题，不影响链路本身。

## page4 已对齐的方法

- `tablet_set_alarm(hour, minute, label)`
- `tablet_open_app(bundleName)`
- `tablet_list_alarm()`
- `tablet_start_ability(bundleName, abilityName, parameters)`
- `tablet_open_url(url)`

## 需要你配置

在 `config/DeviceNetworkConfig.ets` 中设置：

- `TABLET_COMPANION_TOKEN`
- `TABLET_COMPANION_NODE_ID`
- `TABLET_COMPANION_HOST`（可空，默认复用网关候选）

## 网关路由约定

- `POST /v1/tablet/set_alarm`
- `POST /v1/tablet/open_app`
- `POST /v1/tablet/list_alarm`
- `POST /v1/tablet/start_ability`
- `POST /v1/tablet/open_url`

请求体：

```json
{
  "nodeId": "tablet-main",
  "args": {
    "...": "..."
  }
}
```

响应体：

```json
{
  "ok": true,
  "message": "text",
  "data": {}
}
```
