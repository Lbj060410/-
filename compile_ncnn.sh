#!/bin/bash
set -e
echo "开始编译 ncnn for HarmonyOS"
OHOS_NDK="/mnt/host/f/HarmonyOs/Sdk/openharmony/9/native"
NCNN_SRC="$HOME/ncnn"
BUILD_DIR="$HOME/ncnn-build"
OUTPUT="/mnt/host/f/HarmonyOs/car/third_party/ncnn"
echo "[1/6] 检查 NDK..."
ls "$OHOS_NDK/build/cmake/ohos.toolchain.cmake" || exit 1
echo "[2/6] 安装工具..."
sudo apt-get update && sudo apt-get install -y build-essential cmake git
echo "[3/6] 下载 ncnn..."
if [ ! -d "$NCNN_SRC" ]; then
    git clone --depth=1 https://github.com/Tencent/ncnn.git "$NCNN_SRC"
fi
echo "[4/6] 配置..."
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
cmake "$NCNN_SRC" -DCMAKE_TOOLCHAIN_FILE="$OHOS_NDK/build/cmake/ohos.toolchain.cmake" -DCMAKE_BUILD_TYPE=Release -DOHOS_ARCH=arm64-v8a -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" -DNCNN_VULKAN=OFF -DNCNN_OPENMP=OFF -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF
echo "[5/6] 编译..."
make -j4 && make install
echo "[6/6] 复制..."
mkdir -p "$OUTPUT/include" "$OUTPUT/lib/arm64-v8a"
cp -r "$BUILD_DIR/install/include/ncnn/"* "$OUTPUT/include/"
cp "$BUILD_DIR/install/lib/libncnn.a" "$OUTPUT/lib/arm64-v8a/"
echo "✅ 完成！"
