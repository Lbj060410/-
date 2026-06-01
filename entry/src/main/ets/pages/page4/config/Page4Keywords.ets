export class Page4Keywords {
  static readonly PLACE_NAME_HOME: string = '物流中心'
  static readonly PLACE_NAME_COMPANY: string = '快递点'
  static readonly PLACE_NAME_COMPANY_ALT: string = ''

  static readonly MULTI_TASK_CONNECTORS: Array<string> = [
    '然后', '接着', '随后', '并且', '并且再', '同时', '接下来', '再去', '再到'
  ]

  static readonly MULTI_TASK_MARKERS: Array<string> = [
    '然后', '接着', '并且', '同时', '再', '随后', ';', '；', ',', '，'
  ]

  static readonly CONTROL_ACTION_REPEAT: Array<string> = ['再来一次', '重复上一动作', '继续刚才动作', 'repeat']
  static readonly ACTION_SCRAM: Array<string> = ['紧急停止', '急停', 'scram']
  static readonly ACTION_STOP: Array<string> = ['停止', '停车', 'stop']
  static readonly ACTION_GO: Array<string> = ['前进', '向前', 'go']
  static readonly ACTION_BACK: Array<string> = ['后退', '倒车', 'back']
  static readonly ACTION_LEFT: Array<string> = ['左转']
  static readonly ACTION_RIGHT: Array<string> = ['右转']
  static readonly ACTION_UTURN: Array<string> = ['掉头']

  static readonly AUTO_FOLLOW_ON: Array<string> = ['开启自动跟随', '打开自动跟随', '自动跟随开启', '自动驾驶开启']
  static readonly AUTO_FOLLOW_OFF: Array<string> = ['关闭自动跟随', '停止自动跟随', '自动跟随关闭', '自动驾驶关闭']
  static readonly SEND_MODE_REAL: Array<string> = ['开启真车模式', '真车模式', 'real_send']
  static readonly SEND_MODE_DRY: Array<string> = ['开启仿真模式', '仿真模式', 'dry_run', '关闭真车模式']

  static readonly QUERY_STATUS: Array<string> = ['查询状态', '状态', 'status']
  static readonly QUERY_VISION: Array<string> = ['识别状态', '视觉状态', '识别结果', 'vision']
  static readonly QUERY_COMM: Array<string> = ['网络', '通信']
  static readonly QUERY_VIDEO: Array<string> = ['视频', '相机']
  static readonly CAPTURE_FRAME: Array<string> = [
    '获取当前摄像头画面',
    '获取当前画面',
    '抓取当前画面',
    '读取当前画面',
    '保存当前画面',
    '给我当前画面',
    '看一下当前画面',
    'camera frame',
    'current frame',
    'capture frame'
  ]

  static readonly BATTERY_QUERY_LOWER: Array<string> = ['电量', '电池', 'battery', '多少电', '剩余电量', '当前电量']
  static readonly BATTERY_QUERY_TEXT: Array<string> = ['还有多少电', '还剩多少电', '目前多少电']

  static readonly ORDER_QUERY_DOMAIN: Array<string> = ['订单', '出库单', '订单记录', '拣货', '复核', '发货', '出库']
  static readonly ORDER_QUERY_VERBS: Array<string> = ['查', '查询', '查找', '查看', '看看', '给我', '列出', '统计', '记录']
  static readonly ORDER_QUERY_STATUS_SHIPPED: Array<string> = ['已发货']
  static readonly ORDER_QUERY_SCOPE_EARLIEST: Array<string> = ['最早']
  static readonly ORDER_QUERY_SCOPE_LATEST: Array<string> = ['最晚', '最新']
  static readonly ORDER_QUERY_SCOPE_ALL: Array<string> = ['全部', '所有']
  static readonly ORDER_STATUS_SHIPPED_TEXT: string = '已发货'

  static readonly ROUTE_HOME_SHORTCUT_RAW: Array<string> = [
    '前往物流中心', '去物流中心', '到物流中心', '返回物流中心', '回物流中心',
    '返仓', '回仓', '返航', '回基地', '返回基地', '回中心'
  ]
  static readonly ROUTE_HOME_SHORTCUT_LOWER: Array<string> = []
  static readonly ROUTE_COMPANY_SHORTCUT_RAW: Array<string> = [
    '前往快递点', '去快递点', '到快递点', '返回快递点', '回快递点',
    '前往快递网点', '去快递网点', '到快递网点', '返回快递网点', '回快递网点'
  ]
  static readonly ROUTE_COMPANY_SHORTCUT_LOWER: Array<string> = []
  static readonly ROUTE_WAREHOUSE_SHORTCUT_RAW: Array<string> = ['前往仓库', '去仓库', '到仓库', '回仓库', '返回仓库']

  static readonly ROUTE_TARGET_DISPLAY_HOME_RAW: Array<string> = [
    '物流中心', '回仓', '返仓', '返航', '回基地', '回中心'
  ]
  static readonly ROUTE_TARGET_DISPLAY_HOME_LOWER: Array<string> = []
  static readonly ROUTE_TARGET_DISPLAY_COMPANY_RAW: Array<string> = [
    '快递点', '快递网点', '回快递点', '返回快递点'
  ]
  static readonly ROUTE_TARGET_DISPLAY_COMPANY_LOWER: Array<string> = []

  static readonly CONTROL_INTENT: Array<string> = [
    '导航', '前往', '去', '到',
    '返仓', '回仓', '返航', '回基地', '回中心', '回物流中心', '回快递点', '回仓库', '返仓库',
    '前进', '后退', '左转', '右转', '掉头', '停止', '急停', '刹车',
    '自动跟随', '自动驾驶', '真车模式', '仿真模式', 'real_send', 'dry_run',
    '撤销', '回到安全点',
    '抓拍', '截图', '拍照', '相机', '视频',
    '查询状态', '状态', '识别', '视觉', '通信', '网络',
    '读取文件', '读文件', '文件内容', '进程列表', '查询进程', '执行命令', '命令行', 'process', 'read_file', 'exec_cmd'
  ]

  static readonly HELP_QUERY: Array<string> = ['示例', '例子', 'help', '帮助', '怎么用']
  static readonly UNDO_QUERY: Array<string> = ['撤销', 'undo', '回到上一个安全点', '回到安全点']
  static readonly ADAPTIVE_STRATEGY_QUERY: Array<string> = ['夜间策略', '弱网策略', '稳态策略', '稳定策略']
  static readonly ROUTE_REASON_QUERY: Array<string> = ['导航失败原因', '失败原因', '重规划方案', '为什么失败']
  static readonly POI_MAPPING_QUERY: Array<string> = ['所有点位', '点位映射', '映射名称', '点位列表', '全部点位', '查看所有映射点位']
  static readonly EXPORT_POI_QUERY: Array<string> = ['导出点位映射', '导出映射', '导出点位', '导出json', '导出为json']

  static readonly PLACE_ROLE_HOME_TOKENS: Array<string> = ['物流中心']
  static readonly PLACE_ROLE_COMPANY_TOKENS: Array<string> = ['快递点', '快递网点']
  static readonly PLACE_BINDING_ROLE_TOKENS: Array<string> = ['物流中心', '快递点', '快递网点']
  static readonly PLACE_BINDING_SETTERS: Array<string> = ['设置为', '设为', '改为', '改成', '定义为', '记为', '当成', '作为']
  static readonly PLACE_BINDING_QUERY_ROLES: Array<string> = ['物流中心', '快递点', '快递网点']
  static readonly PLACE_BINDING_QUERY_VERBS: Array<string> = ['在哪', '是什么', '查询', '查看', '配置', '设置了吗', '有没有设置', '是否设置']
  static readonly PLACE_BINDING_INTENT_BLOCKERS: Array<string> = ['映射', '点位', '查询', '查看', '有没有', '是否']
  static readonly PLACE_BINDING_QUERY_HOME: Array<string> = ['物流中心']
  static readonly PLACE_BINDING_QUERY_COMPANY: Array<string> = ['快递点', '快递网点']

  static readonly ALIAS_LEARN_PATTERNS: Array<RegExp> = [
    /(?:把|将)?\s*([^，。；;,\s]{1,16})\s*(?:记为|设为|设置为|定义为)\s*([A-Ga-g]\d{1,2})/,
    /^([^，。；;,\s]{1,16})\s*(?:是|等于)\s*([A-Ga-g]\d{1,2})$/
  ]
  static readonly CONTEXT_DEST_REFERENCES: Array<string> = ['那里', '那儿', '刚才那个点', '上一目的地', '上一个目的地', '原目的地']

  static buildMultiTaskConnectorRegex(): RegExp {
    return /然后|接着|随后|并且|并且再|同时|接下来|再去|再到/g
  }

  static buildMultiTaskSeparatorRegex(): RegExp {
    return /[，,；;。.!！?？\n]/g
  }

  static buildRouteTargetRegex(): RegExp {
    return /(?:导航到|前往|去|到达|前进到)\s*([A-Z]\d{1,2})/
  }

  static buildRouteAntiSourceRegex(): RegExp {
    return /(?:离开|从|出发|起点|LEAVE|FROM|DEPART)\s*([A-Z]\d{1,2})/
  }

  static buildGridNodeRegex(): RegExp {
    return /\b([A-Z]\d{1,2})\b/
  }

  static buildOrderIdRegex(): RegExp {
    return /OUT-\d{8}-\d{3}/i
  }

  static buildOrderSkuRegex(): RegExp {
    return /[A-Z]{2}-\d{4}/i
  }

  static buildPlaceBindingRoleFirstRegex(): RegExp {
    return /(?:把|将)?\s*(物流中心|快递点|快递网点)\s*(?:设置为|设为|改为|改成|定义为|记为)\s*(.+)$/i
  }

  static buildPlaceBindingPlaceFirstRegex(): RegExp {
    return /(?:把|将)?\s*(.+?)\s*(?:设置为|设为|改为|改成|定义为|记为)\s*(物流中心|快递点|快递网点)\s*$/i
  }
}
