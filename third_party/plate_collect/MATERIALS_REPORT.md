# 车牌方案一材料清单（自动提取）

## 已提取（来自旧安卓项目）
- 旧项目路径：`F:\Androidcar\ML_lik_car (3)\ML_lik_car`
- 提取目录：`F:\HarmonyOs\car\third_party\plate_collect`
- 关键目录已复制：`libs/` `jniLibs/` `assets/`
- 关键参考代码已复制：
  - `init_ref\...CarPlate1.java`
  - `init_ref\...yolov5__CarPlate.java`
  - `init_ref\...BKRC_recognize__CarPlate.java`
- Gradle 缓存中已找到 HyperLPR3：
  - `maven_cache\...hyperlpr3-android-sdk-1.0.3.aar`
  - `maven_cache\...hyperlpr3-android-sdk-1.0.3.pom`
  - `maven_cache\...hyperlpr3-android-sdk-1.0.3-sources.jar`

## 代码线索（已确认）
- `app/build.gradle` 存在依赖：`com.github.HyperInspire:hyperlpr3-android-sdk:1.0.3`
- 参考调用在：`CarPlate.java`/`CarPlate1.java`/`MainActivity.java`
- 典型初始化参数：
  - `setDetLevel(HyperLPR3.DETECT_LEVEL_LOW)`
  - `setMaxNum(1~2)`
  - `setRecConfidenceThreshold(0.85f)`

## 仍需补齐（关键）
- Harmony 可直接接入的 SDK：`HAR/HSP` 或 Harmony NAPI 可用的 `so + 头文件`
- 对应授权材料：`license/key`（若 SDK 要求）
- Harmony 版 API 文档（init / recognize / release）

## 结论
- 你旧项目的安卓侧材料我已经帮你集中并整理好了。
- 下一步要在 Harmony 达到安卓同等级车牌识别，仍需“Harmony 兼容 SDK + 授权 + 文档”。
