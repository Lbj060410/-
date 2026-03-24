package com.example.ml_lik_car;


import static com.example.ml_lik_car.BitmapHandle.findCorner;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.renderscript.Allocation;
import android.renderscript.Element;
import android.renderscript.RenderScript;
import android.renderscript.ScriptIntrinsicBlur;
import android.util.Log;
import android.widget.ImageView;
import android.widget.TextView;

import com.hyperai.hyperlpr3.HyperLPR3;
import com.hyperai.hyperlpr3.bean.Plate;


public class CarPlate1 {

    public static String RY_PlateResult;
    public static String DC_PlateResult;
    public static String QT_PlateResult;

    static Handler handler = new Handler(Looper.getMainLooper());
    public static String typeDescription;
    public static String Carplate_result;
    public static char[] car_arryplate = new char[0];

    /**
     * 车牌识别并返回处理后的 Bitmap（车牌区域已模糊）
     */
    @SuppressLint("SetTextI18n")
    public static Bitmap carTesseractProcessed(Bitmap bitmap, Context context, TextView textView, ImageView imageView) {
        if (bitmap == null) return null;

        // 复制一份用于处理
        Bitmap bcopy = bitmap.copy(Bitmap.Config.ARGB_8888, true);
        Bitmap copyShow = bitmap.copy(Bitmap.Config.ARGB_8888, true);
        Canvas canvasShow = new Canvas(copyShow);
        Paint paintShow = new Paint();
        paintShow.setStyle(Paint.Style.STROKE);
        paintShow.setStrokeWidth(2);
        paintShow.setColor(0xFFFF0000); // 红色边框

        RY_PlateResult = "";
        DC_PlateResult = "";
        QT_PlateResult = "";

        StringBuilder car = new StringBuilder();

        try {
            while (true) {
                Plate[] plates = HyperLPR3.getInstance().plateRecognition(bcopy, HyperLPR3.CAMERA_ROTATION_0, HyperLPR3.STREAM_BGRA);
                if (plates[0] == null) break;

                Rect rect = new Rect((int) plates[0].getX1(), (int) plates[0].getY1(),
                        (int) plates[0].getX2(), (int) plates[0].getY2());

                // 对车牌区域进行模糊处理
                blurRegion(context, bcopy, rect, 25f); // 25f 是模糊半径，可调节
//                resetRegionPixels(bcopy,rect, android.R.color.black);
                // 绘制边框显示
                canvasShow.drawRect(rect, paintShow);

                switch (plates[0].getType()) {
                    case 0: typeDescription = "（燃油）"; break;
                    case 3: typeDescription = "（电车）"; break;
                    default: typeDescription = "（燃油）"; break;
                }

                Carplate_result = plates[0].getCode().substring(1);
                if (plates[0].getType() == 0) {
                    RY_PlateResult = Carplate_result;
                    car.append("国").append(RY_PlateResult).append("（燃油）").append("\n");
                } else if (plates[0].getType() == 3) {
                    DC_PlateResult = Carplate_result;
                    car.append("国").append(DC_PlateResult).append("（电车）").append("\n");
                } else {
                    RY_PlateResult = Carplate_result;
                    car.append("国").append(QT_PlateResult).append("（其他）").append("\n");
                }
            }
        } catch (Exception ignored) {
        }

        StringBuilder finalCar = car;
        handler.post(() -> {
            if (textView != null) textView.setText("\n车牌识别结果：\n" + finalCar + "（车牌识别结果）");
            if (imageView != null) imageView.setImageBitmap(copyShow);
        });

        return bcopy;
    }

    /**
     * 使用 RenderScript 对指定区域进行高斯模糊
     */
    private static void blurRegion(Context context, Bitmap bmp, Rect rect, float radius) {
        if (bmp == null || radius <= 0) return;
        int left = Math.max(0, rect.left);
        int top = Math.max(0, rect.top);
        int right = Math.min(bmp.getWidth(), rect.right);
        int bottom = Math.min(bmp.getHeight(), rect.bottom);

        Bitmap regionBmp = Bitmap.createBitmap(bmp, left, top, right - left, bottom - top);

        RenderScript rs = RenderScript.create(context);
        Allocation input = Allocation.createFromBitmap(rs, regionBmp);
        Allocation output = Allocation.createTyped(rs, input.getType());
        ScriptIntrinsicBlur blur = ScriptIntrinsicBlur.create(rs, Element.U8_4(rs));
        blur.setRadius(Math.min(25f, radius)); // RenderScript 最大支持 25f
        blur.setInput(input);
        blur.forEach(output);
        output.copyTo(regionBmp);
        rs.destroy();

        // 将模糊后的区域覆盖回原图
        Canvas canvas = new Canvas(bmp);
        canvas.drawBitmap(regionBmp, left, top, null);
    }
    public static Bitmap resetRegionPixels(Bitmap original, Rect location, int color) {
        // 复制一张Bitmap，不修改原图
        Bitmap result = original.copy(Bitmap.Config.ARGB_8888, true);

        int left = Math.max(0, Math.round(location.left));
        int top = Math.max(0, Math.round(location.top));
        int right = Math.min(result.getWidth(), Math.round(location.right));
        int bottom = Math.min(result.getHeight(), Math.round(location.bottom));

        // 遍历区域内所有像素，设置为固定颜色
        for (int y = top; y < bottom; y++) {
            for (int x = left; x < right; x++) {
                result.setPixel(x, y, color);
            }
        }

        return result;
    }
}
