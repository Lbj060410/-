# ncnn HarmonyOS 编译指南

## 前置条件
- ✅ WSL (Windows Subsystem for Linux)
- ✅ HarmonyOS SDK 9 Native

## 编译步骤

### 1. 启动 WSL
```bash
# 在 Windows PowerShell 或 CMD 中执行
wsl
```

### 2. 进入项目目录
```bash
cd /mnt/f/HarmonyOs/car
```

### 3. 运行编译脚本
```bash
chmod +x build_ncnn_ohos.sh
./build_ncnn_ohos.sh
```

### 4. 等待编译完成（约 5-10 分钟）

编译过程会：
- 下载 ncnn 源码
- 使用 HarmonyOS NDK 交叉编译
- 生成 libncnn.a 静态库
- 自动复制到 third_party/ncnn/

## 编译选项说明

```cmake
-DNCNN_VULKAN=OFF          # 关闭 Vulkan GPU 加速（避免依赖）
-DNCNN_OPENMP=OFF          # 关闭 OpenMP（避免链接错误）
-DNCNN_BUILD_EXAMPLES=OFF  # 不编译示例
-DNCNN_BUILD_TOOLS=OFF     # 不编译工具
```

## 常见问题

### Q1: 找不到 ohos.toolchain.cmake
**A:** 检查 HarmonyOS SDK 路径是否正确：
```bash
ls /mnt/f/HarmonyOs/Sdk/openharmony/9/native/build/cmake/
```

### Q2: 编译失败 - 找不到编译器
**A:** 安装编译工具：
```bash
sudo apt-get update
sudo apt-get install build-essential cmake
```

### Q3: 权限错误
**A:** 给脚本添加执行权限：
```bash
chmod +x build_ncnn_ohos.sh
```

### Q4: 网络问题无法下载 ncnn
**A:** 手动下载：
```bash
git clone https://github.com/Tencent/ncnn.git ~/ncnn
```

## 编译成功后

### 1. 启用 ncnn 链接
编辑 `entry/src/main/cpp/CMakeLists.txt`，取消注释：
```cmake
if(ENABLE_NCNN)
    target_link_libraries(entry PUBLIC ${NCNN_LIB_DIR}/libncnn.a)
endif()
```

### 2. 取消注释推理代码
编辑 `entry/src/main/cpp/ncnn_detector.cpp`，取消注释：
```cpp
#include "net.h"
#include "mat.h"
```

### 3. 重新编译项目
在 DevEco Studio 中：
- Build → Clean Project
- Build → Rebuild Project

## 验证

编译成功后，检查文件：
```bash
ls -lh /mnt/f/HarmonyOs/car/third_party/ncnn/lib/arm64-v8a/libncnn.a
```

应该看到一个 2-5 MB 的静态库文件。

## 性能优化（可选）

如果需要更好的性能，可以启用 NEON 优化：
```cmake
-DNCNN_ARM82=ON
-DNCNN_ARM82DOT=ON
```

## 故障排除

如果编译失败，查看详细日志：
```bash
./build_ncnn_ohos.sh 2>&1 | tee build.log
```

然后把 `build.log` 发给我分析。
