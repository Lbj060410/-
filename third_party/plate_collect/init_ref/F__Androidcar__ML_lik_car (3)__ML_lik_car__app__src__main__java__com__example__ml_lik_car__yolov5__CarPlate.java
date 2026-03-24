package com.example.ml_lik_car.yolov5;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.ImageView;
import android.widget.TextView;

import com.example.ml_lik_car.MainActivity;
import com.hyperai.hyperlpr3.HyperLPR3;
import com.hyperai.hyperlpr3.bean.HyperLPRParameter;
import com.hyperai.hyperlpr3.bean.Plate;


public class CarPlate{



    // 创建一个Handler，用于在主线程上更新UI
    static Handler handler = new Handler(Looper.getMainLooper());
     public static String typeDescription;
   public static StringBuilder finalCar = null;
   public  static  String carplate;
    private static String  RY_PlateResult;
    //保存电车的车牌号
    private static String  DC_PlateResult;
    //保存其他车的车牌号
    private static String  QT_PlateResult;
    /**
     * 车牌识别方法，依赖HyperLPR3的SDK进行车牌识别
     *jklsd
     * @param bitmap  输入的位图（Bitmap），即要识别的图片
//     * @param context 上下文，用于显示Toast或Dialog
     * @param textView 用于显示识别结果的TextView
     * @param imageView 用于显示带有识别框的图片的ImageView
     * @return 识别到的车牌信息（如果识别成功），否则返回null
     */
    @SuppressLint("SetTextI18n")
    public static StringBuilder carTesseract(Bitmap bitmap, Context context, TextView textView, ImageView imageView) {

        HyperLPRParameter parameter = new HyperLPRParameter()
                .setDetLevel(HyperLPR3.DETECT_LEVEL_LOW)
                .setMaxNum(2) //识别最大数量
                .setRecConfidenceThreshold(0.85f);
// Initialization (performed only once)
        HyperLPR3.getInstance().init(context, parameter);



        Log.e("进入测试1","进入进入进入" );
       // 用于存储最终的车牌识别结果
        StringBuilder car_text = null;
        if (bitmap != null) {
            Log.e("进入测试2","进入进入进入" );
            // 复制原始Bitmap，避免修改原始图片
            Bitmap bcopy = bitmap.copy(Bitmap.Config.ARGB_8888, true);
            // 复制一份用于显示的Bitmap，上面将绘制识别框
            Bitmap copyShow = bitmap.copy(Bitmap.Config.ARGB_8888, true);
            Log.e("进入测试2.5","进入进入进入" );
            Canvas canvasShow = new Canvas(copyShow);
            Log.e("进入测试2.6","进入进入进入" );
            Paint paintShow = new Paint();
            Log.e("进入测试2.7","进入进入进入" );
            // 设置绘制识别框的颜色、样式和宽度
            paintShow.setColor(Color.RED);
            Log.e("进入测试2.8","进入进入进入" );
            paintShow.setStyle(Paint.Style.STROKE);
            Log.e("进入测试2.9","进入进入进入" );
            paintShow.setStrokeWidth(2);
            Log.e("进入测试3.0","进入进入进入" );
            StringBuilder car = new StringBuilder();
            car_text = new StringBuilder();
            try {
                Log.e("进入测试6","进入进入进入" );
                // 使用HyperLPR3进行车牌识别
                Plate[] plates = HyperLPR3.getInstance().plateRecognition(bcopy, HyperLPR3.CAMERA_ROTATION_0, HyperLPR3.STREAM_BGRA);
                Log.e("进入测试7","进入进入进入" );
                if (plates.length >= 0) {
                    Log.e("进入测试3","进入进入进入" );
                    // 在识别到的车牌位置绘制一个红色的矩形框
                    canvasShow.drawRect(new Rect((int) plates[0].getX1() + 5, (int) plates[0].getY1() + 5, (int) plates[0].getX2() + 5, (int) plates[0].getY2() + 5), paintShow);
                    // 根据车牌类型添加描述（燃油、电车、其他）

//                    switch (plates[0].getType()) {
//                        case 0:
//                            typeDescription = "（燃油）";
//                            break;
//                        case 3:
//                            typeDescription = "（电车）";
//                            break;
//                        default:
//                            typeDescription = "（其他）";
//                            break;
//                    }
                    if (plates[0].getType() == 0) {
                        RY_PlateResult = plates[0].getCode().substring(1);
                        car.append("国").append(plates[0].getCode().substring(1)).append("（燃油）").append("\n");
                    } else if (plates[0].getType() == 3) {
                        //保存电车的车牌号
                        DC_PlateResult = plates[0].getCode().substring(1);
                        car.append("国").append(plates[0].getCode().substring(1)).append("（电车）").append("\n");
                    } else {
                        //保存其他车的车牌号
                        QT_PlateResult = plates[0].getCode().substring(1);
                        car.append("国").append(plates[0].getCode().substring(1)).append("（其他）").append("\n");
                    }
                    // 构建最终的车牌信息，并赋值给finalCar
                    carplate= plates[0].getCode();
                    car.append("国").append(plates[0].getCode().substring(1)).append(typeDescription).append("\n");
                    car_text.append(plates[0].getCode().substring(1));
                    finalCar = car;
                    // 打印识别到的车牌信息
                    Log.e("carTesseract: ", plates[0].toString());
                }else {
                    Log.e( "未进入if ","nonononono" );
                }
            } catch (Exception ignored) {
                Log.e("进入测试4","进入进入进入" );

                // 忽略异常，不进行任何处理（即不赋值给finalCar）
            }
            // 根据finalCar是否为null，更新UI
            if (finalCar != null) {
                Log.e("进入测试5 ","进入进入进入" );
                StringBuilder finalCar1 = finalCar;
                handler.post(() -> {
                    if (textView != null) {
                        // 如果textView不为null，则在textView中显示识别结果，并在imageView中显示带有识别框的图片
                        textView.setText(finalCar1 + "（识别结果仅供参考）\n");
                        imageView.setImageBitmap(copyShow);
                    } else {
                        // 如果textView为null，则创建一个对话框显示识别结果和图片
                        textView.setText(finalCar1 + "（识别结果仅供参考）\n");
                    }
                });
            }
        }
        // 返回车牌识别结果，仅返回数字和字母部分（如果识别成功），否则返回null
        Log.d("CarPlate", "车牌号：" + car_text);
        return car_text;
    }
}