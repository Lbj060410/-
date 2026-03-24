#!/bin/bash
# ncnn HarmonyOS 编译脚本
# 使用方法：在 WSL 中运行此脚本

set -e  # 遇到错误立即退出

echo "=========================================="
echo "ncnn HarmonyOS 编译脚本"
echo "=========================================="

# 配置变量
OHOS_NDK_PATH="/mnt/f/HarmonyOs/Sdk/openharmony/9/native"
NCNN_SOURCE_DIR="$HOME/ncnn"
BUILD_DIR="$HOME/ncnn-build-ohos"
OUTPUT_DIR="/mnt/f/HarmonyOs/car/third_party/ncnn"

# 检查 HarmonyOS NDK
echo ""
echo "[1/7] 检查 HarmonyOS NDK..."
if [ ! -d "$OHOS_NDK_PATH" ]; then
    echo "❌ 错误：找不到 HarmonyOS NDK: $OHOS_NDK_PATH"
    echo "请确认路径是否正确"
    exit 1
fi

if [ ! -f "$OHOS_NDK_PATH/build/cmake/ohos.toolchain.cmake" ]; then
    echo "❌ 错误：找不到 ohos.toolchain.cmake"
    exit 1
fi

echo "✅ HarmonyOS NDK 路径正确"

# 安装编译工具
echo ""
echo "[2/7] 安装编译工具..."
sudo apt-get update
sudo apt-get install -y build-essential cmake git wget

# 下载 ncnn 源码
echo ""
echo "[3/7] 下载 ncnn 源码..."
if [ ! -d "$NCNN_SOURCE_DIR" ]; then
    git clone --depth=1 https://github.com/Tencent/ncnn.git "$NCNN_SOURCE_DIR"
else
    echo "ncnn 源码已存在，跳过下载"
fi

cd "$NCNN_SOURCE_DIR"

# 创建构建目录
echo ""
echo "[4/7] 创建构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 配置 CMake
echo ""
echo "[5/7] 配置 CMake..."
cmake "$NCNN_SOURCE_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK_PATH/build/cmake/ohos.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DOHOS_ARCH=arm64-v8a \
    -DOHOS_PLATFORM=OHOS \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
    -DNCNN_VULKAN=OFF \
    -DNCNN_OPENMP=OFF \
    -DNCNN_BUILD_EXAMPLES=OFF \
    -DNCNN_BUILD_TOOLS=OFF \
    -DNCNN_BUILD_BENCHMARK=OFF \
    -DNCNN_BUILD_TESTS=OFF \
    -DNCNN_PIXEL=ON \
    -DNCNN_PIXEL_ROTATE=OFF \
    -DNCNN_PIXEL_AFFINE=OFF \
    -DNCNN_PIXEL_DRAWING=OFF

# 编译
echo ""
echo "[6/7] 开始编译（这可能需要 5-10 分钟）..."
make -j$(nproc)
make install

# 复制到项目
echo ""
echo "[7/7] 复制库文件到项目..."
mkdir -p "$OUTPUT_DIR/include"
mkdir -p "$OUTPUT_DIR/lib/arm64-v8a"

cp -r "$BUILD_DIR/install/include/ncnn/"* "$OUTPUT_DIR/include/"
cp "$BUILD_DIR/install/lib/libncnn.a" "$OUTPUT_DIR/lib/arm64-v8a/"

echo ""
echo "=========================================="
echo "✅ 编译完成！"
echo "=========================================="
echo ""
echo "输出位置："
echo "  头文件: $OUTPUT_DIR/include/"
echo "  库文件: $OUTPUT_DIR/lib/arm64-v8a/libncnn.a"
echo ""
echo "下一步："
echo "  1. 在 DevEco Studio 中取消注释 ncnn_detector.cpp 的推理代码"
echo "  2. 在 CMakeLists.txt 中启用 ncnn 链接"
echo "  3. 重新编译项目"
echo ""
