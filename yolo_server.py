"""
YOLOv5 HTTP Detection Server
接收 JPEG bytes，返回归一化 bbox JSON

用法：
  pip install flask torch torchvision
  python yolo_server.py

可选参数（环境变量）：
  MODEL=yolov5s   # yolov5n / yolov5s / yolov5m / yolov5l / yolov5x
  PORT=5000
  CONF=0.4        # 置信度阈值
"""

import io
import os
import time

import torch
from flask import Flask, jsonify, request
from PIL import Image

MODEL_NAME = os.environ.get('MODEL', 'yolov5s')
PORT = int(os.environ.get('PORT', 5000))
CONF_THRESH = float(os.environ.get('CONF', 0.4))

print(f'Loading {MODEL_NAME} ...')
model = torch.hub.load('ultralytics/yolov5', MODEL_NAME, pretrained=True)
model.conf = CONF_THRESH
model.eval()
print(f'{MODEL_NAME} loaded, conf={CONF_THRESH}')

app = Flask(__name__)


@app.route('/detect', methods=['POST'])
def detect():
    t0 = time.time()

    try:
        img = Image.open(io.BytesIO(request.data)).convert('RGB')
    except Exception as e:
        return jsonify({'boxes': [], 'costMs': 0, 'error': str(e)}), 400

    w, h = img.size

    with torch.no_grad():
        results = model(img)

    boxes = []
    for *xyxy, conf, cls in results.xyxy[0].tolist():
        x1, y1, x2, y2 = xyxy
        boxes.append({
            'label': model.names[int(cls)],
            'score': round(conf, 3),
            'x': round(x1 / w, 4),
            'y': round(y1 / h, 4),
            'w': round((x2 - x1) / w, 4),
            'h': round((y2 - y1) / h, 4),
        })

    cost_ms = int((time.time() - t0) * 1000)
    print(f'[detect] {w}x{h} boxes={len(boxes)} cost={cost_ms}ms')
    return jsonify({'boxes': boxes, 'costMs': cost_ms})


@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({'ok': True, 'model': MODEL_NAME, 'conf': CONF_THRESH})


if __name__ == '__main__':
    print(f'Server starting on 0.0.0.0:{PORT}')
    app.run(host='0.0.0.0', port=PORT, debug=False)
