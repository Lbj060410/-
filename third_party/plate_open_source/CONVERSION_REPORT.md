# Plate Model Conversion Report

## Inputs
- Source project: `F:\chinese-license-plate-recognition-master\chinese-license-plate-recognition-master\Chinese_license_plate_detection_recognition-main`
- Python env: `F:\yolov5master\yolov5\yolov5_env\Scripts\python.exe`
- Conversion tools:
  - `F:\ocnn\pnnx-20260112-windows\pnnx.exe`
  - `F:\ocnn\ncnn-20260113-windows-vs2022\x64\bin\...`

## Outputs
Generated under `F:\HarmonyOs\car\third_party\plate_open_source\weights`:

- Detection model:
  - `plate_detect.onnx`
  - `plate_detect.ncnn.param`
  - `plate_detect.ncnn.bin`
  - `plate_detect.pnnx.param`
  - `plate_detect.pnnx.bin`
- Recognition model:
  - `plate_rec_color.onnx`
  - `plate_rec_color.ncnn.param`
  - `plate_rec_color.ncnn.bin`
  - `plate_rec_color.pnnx.param`
  - `plate_rec_color.pnnx.bin`

## Notes
- `export.py` ends with `ModuleNotFoundError: onnxruntime`, but ONNX export succeeds before that step.
- Added helper script:
  - `F:\HarmonyOs\car\third_party\plate_open_source\export_plate_rec_onnx.py`

## Current Integration Blocker
- Current Harmony native inference path links only MindSpore Lite and accepts only `OH_AI_MODELTYPE_MINDIR`.
- SDK header confirms only `MINDIR` is supported in current API.
- Therefore ONNX/NCNN artifacts are prepared, but cannot be executed by current app runtime without:
  1. MindSpore converter to generate `.ms/.mindir`, or
  2. Harmony-compatible NCNN runtime integration (source or OHOS target libs).
