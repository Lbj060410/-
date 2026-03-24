#!/usr/bin/env python3
"""
将安卓项目的 .tflite 模型批量转换为 .onnx
"""
import os
import subprocess
from pathlib import Path

# 源目录（安卓项目）
SOURCE_DIR = r"F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets"
# 目标目录（HarmonyOS 项目）
TARGET_DIR = r"F:\HarmonyOs\car\entry\src\main\resources\rawfile"

# 需要转换的模型列表
MODELS = [
    "honglvdeng-fp16.tflite",
    "traffic_sign-fp16.tflite",
    "Car_plant_more2.tflite",
    "Car_plant_one.tflite",
    "JT_BZ_mini.tflite",
    "car_recongnize-fp16.tflite",
    "wwss-fp16.tflite",
    "screen1-fp16.tflite",
]

def convert_tflite_to_onnx(tflite_path: str, onnx_path: str):
    """使用 tf2onnx 转换"""
    cmd = [
        "python", "-m", "tf2onnx.convert",
        "--tflite", tflite_path,
        "--output", onnx_path,
        "--opset", "13"
    ]
    print(f"Converting {Path(tflite_path).name} ...")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"✅ Success: {Path(onnx_path).name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed: {e.stderr}")
        return False

def main():
    # 检查 tf2onnx 是否安装
    try:
        subprocess.run(["python", "-m", "tf2onnx.convert", "--help"],
                      capture_output=True, check=True)
    except:
        print("❌ tf2onnx 未安装，请先运行：pip install tf2onnx")
        return

    os.makedirs(TARGET_DIR, exist_ok=True)

    success_count = 0
    for model_name in MODELS:
        tflite_path = os.path.join(SOURCE_DIR, model_name)
        onnx_name = model_name.replace(".tflite", ".onnx").replace("-fp16", "")
        onnx_path = os.path.join(TARGET_DIR, onnx_name)

        if not os.path.exists(tflite_path):
            print(f"⚠️  跳过（文件不存在）: {model_name}")
            continue

        if convert_tflite_to_onnx(tflite_path, onnx_path):
            success_count += 1

    print(f"\n✅ 转换完成：{success_count}/{len(MODELS)} 个模型")
    print(f"输出目录：{TARGET_DIR}")

if __name__ == "__main__":
    main()
