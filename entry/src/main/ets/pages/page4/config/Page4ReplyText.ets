import { Page4PlaceRole } from '../modules/Page4PoiBindingModule'

export class Page4ReplyText {
  static readonly WELCOME: string = '您好，我是您的智能助理，有什么我可以帮您？'
  static readonly NEW_CHAT_EXISTS: string = '已经在新对话中。'
  static readonly VOICE_REPLY_ON: string = '已开启本机播报。'
  static readonly VOICE_REPLY_OFF: string = '已关闭本机播报。'
  static readonly AUTO_SPEAK_READY: string = '语音播报已开启。'
  static readonly VOICE_BUTTON_IDLE: string = '按住说话'
  static readonly VOICE_BUTTON_PRESSING: string = '继续按住说话'
  static readonly VOICE_BUTTON_RECORDING: string = '松开发送 / 滑动取消'
  static readonly VOICE_HINT: string = '语音输入方式：按住说话，松开发送识别文本。'
  static readonly VOICE_ADAPTER_MISSING: string =
    '当前未接入系统语音识别。可先使用文字输入，后续接入 page4VoiceInputAdapter。'
  static readonly PREVIOUS_BUSY: string = '上一条消息仍在处理中，请稍后。'
  static readonly EMPTY_ASSISTANT_REPLY: string = ''
  static readonly QUERY_THINKING: string = '思考中...'
  static readonly QUERY_PREPARING: string = '整理数据中...'
  static readonly EXAMPLE_TEXT: string =
    '示例指令：\n1. 导航到D4\n2. 前往物流中心 / 回仓 / 返仓 / 回快递点\n3. 前进 / 后退 / 左转 / 右转 / 停止\n4. 开启自动跟随 / 关闭自动跟随\n5. 开启真车模式 / 开启仿真模式\n6. 查询状态\n7. 识别状态\n8. 获取当前摄像头画面\n9. 查看所有点位映射名称\n10. 导出点位映射为JSON\n11. 读取文件 C:\\\\temp\\\\a.txt\n12. 查询进程列表\n13. 执行命令 Get-Process'

  static buildExampleText(): string {
    return `${this.EXAMPLE_TEXT}\n14. 查询小车当前电量`
  }

  static toastAutoSpeakFail(msg: string): string {
    return `自动播报失败：${msg}`
  }

  static toastVoiceReplyUnavailable(msg: string): string {
    return `本机播报不可用：${msg}`
  }

  static voiceInputStartFail(msg: string): string {
    return `语音输入启动失败：${msg}`
  }

  static voiceRecognizeFail(msg: string): string {
    return `语音识别失败：${msg}`
  }

  static voiceNotRecognized(): string {
    return '未识别到语音内容，请重试。'
  }

  static voiceMultiClauseRecognized(count: number): string {
    return `已识别多句指令，共 ${count} 条，开始顺序执行。`
  }

  static placeRoleText(role: '' | Page4PlaceRole): string {
    if (role === 'home') return '物流中心'
    if (role === 'company') return '快递点'
    return '目标点位'
  }

  static formatPlaceBinding(role: Page4PlaceRole, node: string, isValidNode: boolean): string {
    const roleText: string = this.placeRoleText(role)
    const up: string = node.trim().toUpperCase()
    return isValidNode ? `${roleText}=${up}` : `${roleText}=未设置`
  }

  static poiMappingSummary(
    lines: Array<string>,
    homeBindingText: string,
    companyBindingText: string,
    dynamicAliases: Array<string>
  ): string {
    const extraText: string = dynamicAliases.length > 0 ? `；自定义别名=${dynamicAliases.join('，')}` : ''
    return `点位映射(${lines.length}个节点)：\n${lines.join('\n')}\n物流中心/快递点：${homeBindingText}，${companyBindingText}${extraText}`
  }

  static exportPoiMappingsSuccess(path: string): string {
    return `已导出点位映射：${path}`
  }

  static exportPoiMappingsFail(error: string): string {
    return `导出点位映射失败：${error}`
  }

  static placeBindingUnresolved(roleText: string): string {
    return `未识别到可用点位，无法设置${roleText}。请直接说节点（如“将D4设置为${roleText}”）或说可映射地名。`
  }

  static placeBindingSetSuccess(
    roleText: string,
    node: string,
    _sourceText: string,
    _homeText: string,
    _companyText: string
  ): string {
    return `已设置：${roleText}=${node}`
  }

  static placeBindingSetPersistFail(roleText: string, node: string): string {
    return `已设置：${roleText}=${node}，但写入失败（本次运行仍生效）。`
  }

  static invalidRouteNode(dest: string): string {
    return `"${dest}" 不是合法的路网节点，请说如“导航到D4”等有效节点。`
  }

  static routeSuccess(targetText: string, receiptSummary: string): string {
    return `已成功导航到 ${targetText}。执行回执：${receiptSummary}`
  }

  static routeFail(receiptSummary: string): string {
    return `导航失败。执行回执：${receiptSummary}`
  }

  static undoResult(summary: string): string {
    return `撤销结果：${summary}`
  }

  static executeReceipt(summary: string): string {
    return `执行回执：${summary}`
  }

  static actionFail(msg: string): string {
    return `动作失败：${msg}`
  }

  static adaptiveWeakEnabled(): string {
    return '已启用弱网策略：降低识别频率并提升超时阈值。'
  }

  static adaptiveNormalEnabled(): string {
    return '已恢复常规策略。'
  }

  static routeReasonSummary(reason: string, replan: string): string {
    return `导航语义查询：失败原因=${reason}；新方案=${replan}`
  }

  static autoFollowEnabled(): string {
    return '已开启自动跟随。'
  }

  static autoFollowDisabled(): string {
    return '已关闭自动跟随。'
  }

  static sendModeReal(): string {
    return '已切换到 REAL_SEND。'
  }

  static sendModeDry(): string {
    return '已切换到 DRY_RUN。'
  }

  static buildCommSummary(
    commStateText: string,
    connected: boolean,
    reconnectCount: number,
    txPackets: number,
    rxPackets: number
  ): string {
    return `通信状态=${commStateText} | connected=${connected} | reconnect=${reconnectCount} | tx/rx=${txPackets}/${rxPackets}`
  }

  static buildVideoSummary(displayMode: number | string, rtspStateText: string, fps: number | string, statusText: string): string {
    return `视频模式=${displayMode} | rtsp=${rtspStateText} | fps=${fps} | status=${statusText}`
  }

  static latestAckMissing(): string {
    return 'ACK未观测到'
  }

  static receiptDone(done: boolean): string {
    return done ? '完成/已生效' : '未完成'
  }

  static receiptSummaryEmpty(): string {
    return '无执行项'
  }

  static stopActionText(): string {
    return '停止'
  }

  static stopActionFail(msg: string): string {
    return `停止失败(${msg})`
  }

  static undoNoSafePoint(prefix: 'undo' | 'fallback' = 'undo'): string {
    if (prefix === 'fallback') return '回退安全点(未记录安全点)'
    return '撤销-回安全点(未记录安全点)'
  }

  static routeFailReceipt(dest: string, detail: string): string {
    return `导航失败(${dest}:${detail})`
  }

  static routeArrived(dest: string): string {
    return `到达 ${dest}`
  }

  static routeArriveTimeout(dest: string, currentNode: string): string {
    return `等待到达超时(${dest}, 当前=${currentNode})`
  }

  static queryStatusSummary(
    connStateText: string,
    realSendEnabled: boolean,
    autoFollowEnabled: boolean,
    riskText: string,
    riskScore: number,
    txFrames: number,
    rxFrames: number,
    recogText: string
  ): string {
    const mode: string = realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    const recText: string = recogText.length > 0 ? recogText : '-'
    return `链路=${connStateText} | 模式=${mode} | 自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'} | 风险=${riskText}(${riskScore}) | TX/RX=${txFrames}/${rxFrames} | Recog=${recText}`
  }

  static orderQueryNoMatch(queryText: string, statusNeed: string): string {
    if (statusNeed.length > 0) return `订单查询：未找到匹配记录（状态=${statusNeed}，关键词=${queryText}）`
    return `订单查询：未找到匹配记录（关键词=${queryText}）`
  }

  static orderQueryTitle(mode: 'all' | 'earliest' | 'latest', statusNeed: string): string {
    let title: string = '订单查询结果'
    if (mode === 'earliest') title = '订单查询结果（最早）'
    if (mode === 'latest') title = '订单查询结果（最新）'
    if (statusNeed.length > 0) title = `${title}（状态=${statusNeed}）`
    return title
  }

  static orderQueryHeader(
    title: string,
    outCount: number,
    matchedCount: number,
    pendingPick: number,
    picking: number,
    pendingCheck: number,
    shipped: number
  ): string {
    return `${title}(${outCount}条，匹配总数=${matchedCount})：待拣货=${pendingPick}，拣货中=${picking}，待复核=${pendingCheck}，已出库/已发货=${shipped}\n`
  }

  static orderQueryLine(
    index: number,
    orderId: string,
    skuCode: string,
    productName: string,
    quantity: number,
    zone: string,
    status: string,
    createTime: string
  ): string {
    return `${index}. ${orderId} | SKU=${skuCode} | ${productName} | 数量=${quantity} | 区域=${zone} | 状态=${status} | 创建=${createTime}`
  }

  static noVisionResult(): string {
    return '暂无识别结果。'
  }

  static visionFailed(errorText: string): string {
    return `识别失败：${errorText}`
  }

  static visionNoBoxes(): string {
    return '无检测框'
  }

  static visionSummary(engine: string, count: number, labels: string): string {
    return `识别引擎=${engine} | boxes=${count} | ${labels}`
  }

  static openClawTokenMissing(): string {
    return 'OpenClaw token 为空，请在 /sdcard/Download/openclaw.env.json 配置 token 文件。'
  }

  static openClawHostMissing(): string {
    return '未检测到 OpenClaw 主机地址。请在 DeviceNetworkConfig.ets 设置 OPENCLAW_GATEWAY_HOST。'
  }

  static openClawQueryTimeout(): string {
    return '查询超时（45秒），请稍后重试。'
  }
}
