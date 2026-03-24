"""
简单的 YOLO HTTP 推理服务
用于 HarmonyOS 小车项目的远程识别

安装依赖：
pip install flask ultralytics pillow numpy

运行：
python yolo_http_server.py

测试：
curl -X POST http://localhost:5000/detect --data-binary @test.jpg
"""

from flask import Flask, request, jsonify
from ultralytics import YOLO
import numpy as np
from PIL import Image
import io
import traceback

app = Flask(__name__)

# 加载模型（根据需要修改模型路径）
MODELS = {
    'yolov5s': None,  # 通用检测
    'traffic_light': None,  # 交通灯
    'traffic_sign': None,  # 交通标志
}

def load_model(model_name='yolov5s'):
    """延迟加载模型"""
    if MODELS[model_name] is None:
        try:
            # 尝试加载自定义模型，失败则使用预训练模型
            MODELS[model_name] = YOLO(f'{model_name}.pt')
            print(f'✅ Loaded model: {model_name}')
        except:
            MODELS[model_name] = YOLO('yolov5s.pt')
            print(f'⚠️ Using default yolov5s for {model_name}')
    return MODELS[model_name]

@app.route('/detect', methods=['POST'])
def detect():
    """
    检测接口

    请求：
    - Method: POST
    - Body: 图片二进制数据（JPEG/PNG）
    - Query: ?model=yolov5s (可选)

    响应：
    - JSON 数组，每个元素包含：
      {
        "cls": 类别ID,
        "score": 置信度,
        "x": 中心点x (归一化),
        "y": 中心点y (归一化),
        "w": 宽度 (归一化),
        "h": 高度 (归一化)
      }
    """
    try:
        # 获取模型名称
        model_name = request.args.get('model', 'yolov5s')

        # 读取图片
        img_bytes = request.data
        if len(img_bytes) == 0:
            return jsonify({'error': 'Empty image data'}), 400

        img = Image.open(io.BytesIO(img_bytes))

        # 加载并运行模型
        model = load_model(model_name)
        results = model(img, conf=0.3)  # 置信度阈值 0.3

        # 解析结果
        boxes = []
        for r in results:
            for box in r.boxes:
                boxes.append({
                    'cls': int(box.cls[0]),
                    'score': float(box.conf[0]),
                    'x': float(box.xywhn[0][0]),
                    'y': float(box.xywhn[0][1]),
                    'w': float(box.xywhn[0][2]),
                    'h': float(box.xywhn[0][3])
                })

        print(f'✅ Detected {len(boxes)} objects')
        return jsonify(boxes)

    except Exception as e:
        error_msg = f'Error: {str(e)}\n{traceback.format_exc()}'
        print(f'❌ {error_msg}')
        return jsonify({'error': error_msg}), 500

@app.route('/health', methods=['GET'])
def health():
    """健康检查"""
    return jsonify({
        'status': 'ok',
        'models': list(MODELS.keys())
    })

if __name__ == '__main__':
    print('🚀 Starting YOLO HTTP Server...')
    print('📍 Endpoint: http://0.0.0.0:5000/detect')
    print('💡 Usage: POST image binary to /detect')
    app.run(host='0.0.0.0', port=5000, debug=False)
