package com.example.ml_lik_car.BKRC_recognize;




import static com.example.ml_lik_car.BitmapHandle.findCorner;

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

import com.hyperai.hyperlpr3.HyperLPR3;
import com.hyperai.hyperlpr3.bean.Plate;



public class CarPlate {
    //保存燃油车的车牌号
    private static String  RY_PlateResult;
    //保存电车的车牌号
    private static String  DC_PlateResult;
    //保存其他车的车牌号
    private static String  QT_PlateResult;
    static Handler handler = new Handler(Looper.getMainLooper());
    /**
     * 车牌识别示例，依赖HyperLPR3的SDK
     *
     * @param bitmap    传入图片内容
     */
    @SuppressLint("SetTextI18n")
    public static void carTesseract(Bitmap bitmap, Context context, TextView textView, ImageView imageView) {
        new Thread(() -> {
            Log.e( "test_carplate ", "第一步");
            RY_PlateResult="";DC_PlateResult="";QT_PlateResult="";
            StringBuilder car;
            //图片处理
            Bitmap bitmapHandle = findCorner(bitmap,null);
            Log.e( "test_carplate ", "第二步");
            if (bitmapHandle != null) {
                // 使用Bitmap作为图片参数进行车牌识别
                Log.e( "test_carplate ", "第三步");
                Bitmap bcopy = bitmapHandle.copy(Bitmap.Config.ARGB_8888, true);
                Bitmap copyShow = bitmapHandle.copy(Bitmap.Config.ARGB_8888, true);
                // 绘制显示图像的边框基本参数
                Canvas canvasShow = new Canvas(copyShow);
                Paint paintShow = new Paint();
                paintShow.setColor(Color.RED);
                paintShow.setStyle(Paint.Style.STROKE);
                paintShow.setStrokeWidth(2);
                // 记录车牌数据
                car = new StringBuilder();
                // 用于存储检测到的车牌
                try {
                    while (true) {
                        Log.e( "test_carplate ", "第四步");
                        // 进行车牌检测
                        Plate[] plates = HyperLPR3.getInstance().plateRecognition(bcopy, HyperLPR3.CAMERA_ROTATION_0, HyperLPR3.STREAM_BGRA);
                        // 如果没有检测到车牌，结束循环
                        if (plates[0] == null) {
                            break;
                        }
                        // 获取第一个检测到的车牌的坐标并进行遮挡，在复制出来的图片上进行遮挡
                        Canvas canvascopy = new Canvas(bcopy);
                        Paint paint = new Paint();
                        paint.setColor(Color.WHITE);
                        // 将已检测到的车牌区域进行像素级遮挡
                        canvascopy.drawRect(new Rect((int) plates[0].getX1() + 5, (int) plates[0].getY1() + 5, (int) plates[0].getX2() + 5, (int) plates[0].getY2() + 5), paint);
                        // 对显示图像进行边框绘制
                        canvasShow.drawRect(new Rect((int) plates[0].getX1() + 5, (int) plates[0].getY1() + 5, (int) plates[0].getX2() + 5, (int) plates[0].getY2() + 5), paintShow);
                        // 进行文本替换和补充，根据type类型获取车牌类型
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
                        // 对识别内容进行数据合并输出
                        Log.e("carTesseract: ", plates[0].toString());
                    }

                } catch (Exception ignored) {
                    // 抛出数据处理异常
                }
                StringBuilder finalCar = car;
                handler.post(() -> {
                    // 在UI线程更新UI
                    if (finalCar.length() > 5) {
                        if (textView != null) {
                            //发送车牌识别结果给主车
                            //此处我默认发送了燃油车车牌号，到时根据题目进行修改
//                            FirstActivity.Connect_Transport.SendPlateResult(RY_PlateResult);
                            //使用文本框显示结果
                            textView.append("\n车牌识别结果：\n" + finalCar + "（车牌识别结果）");
                            imageView.setImageBitmap(copyShow);
                            Log.d("cpsbbb","燃油车："+ RY_PlateResult);
                            Log.d("cpsbbb","电车:"+ DC_PlateResult);
                            Log.d("cpsbbb","其他："+ QT_PlateResult);
                        } else {
                            // 进行内容弹窗显示
                            //发送车牌识别结果给主车
                            //此处我默认发送了燃油车车牌号，到时根据题目进行修改
//                            FirstActivity.Connect_Transport.SendPlateResult(RY_PlateResult);
//                            RecDialog.createLoadingDialog(context, copyShow, "车牌识别", finalCar + "（识别结果仅供参考）");
                            Log.e( "test_carplate ", "last");
                        }
                    } else {
                        if (textView != null) {
                            textView.append("\n未识别到车牌！");
                        } else {
//                            ToastUtil.ShowToast(context,"未识别到车牌");
                        }
                    }
                });
            }
        }).start();
    }
}
