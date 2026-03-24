@echo off
echo ========================================
echo 转换核心模型 .tflite -> .onnx
echo ========================================

set SOURCE_DIR=F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets
set TARGET_DIR=F:\HarmonyOs\car\entry\src\main\resources\rawfile

echo.
echo [1/3] 转换 traffic_sign (交通标志)...
python -m tf2onnx.convert --tflite "%SOURCE_DIR%\traffic_sign-fp16.tflite" --output "%TARGET_DIR%\traffic_sign.onnx" --opset 13

echo.
echo [2/3] 转换 honglvdeng (红绿灯)...
python -m tf2onnx.convert --tflite "%SOURCE_DIR%\honglvdeng-fp16.tflite" --output "%TARGET_DIR%\honglvdeng.onnx" --opset 13

echo.
echo [3/3] 转换 Car_plant_more2 (车牌)...
python -m tf2onnx.convert --tflite "%SOURCE_DIR%\Car_plant_more2.tflite" --output "%TARGET_DIR%\Car_plant_more2.onnx" --opset 13

echo.
echo ========================================
echo 转换完成！检查输出目录：
echo %TARGET_DIR%
echo ========================================
pause
