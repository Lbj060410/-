export class Page4UiLayer {
  static formatTime(ts: number): string {
    const d: Date = new Date(ts)
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
  }

  static voiceButtonText(voiceRecording: boolean, voicePressing: boolean): string {
    if (voiceRecording) return '松开发送'
    if (voicePressing) return '继续按住说话'
    return '按住说话'
  }

  static displayModeText(v: number): string {
    if (v === 0) return 'RTSP'
    if (v === 1) return 'HTTP'
    if (v === 2) return 'LOCAL'
    return String(v)
  }

  static buildExampleText(): string {
    return '示例指令：\n1. 导航到 D4\n2. 前往物流中心 / 回仓 / 返仓 / 回快递点\n3. 前进 / 后退 / 左转 / 右转 / 停止\n4. 开启自动跟随 / 关闭自动跟随\n5. 开启真车模式 / 开启仿真模式\n6. 查询状态\n7. 识别状态\n8. 获取当前摄像头画面\n9. 查看所有点位映射名称\n10. 导出点位映射为JSON\n11. 读取文件 C:\\\\temp\\\\a.txt\n12. 查询进程列表\n13. 执行命令 Get-Process'
  }
}
