package com.vitalis.vitalis_app.tasks;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.File;
import java.util.List;
import java.util.Map;

/** Explicit RGB preprocessing. Stored pixels are used without EXIF rotation. */
public final class OnnxImageInput {
    private OnnxImageInput() {}
    public static float[] prepare(Context context, File file, long[] shape,
            Map<String, Object> settings, OnnxTaskEngine.Control control, long budget) throws Exception {
        control.check();
        OnnxTaskEngine.requireOwnedFile(context, file);
        String layout = (String)settings.get("layout");
        if (shape.length != 4 || shape[0] != 1 ||
                !("NCHW".equals(layout) || "NHWC".equals(layout)) ||
                !"RGB".equals(settings.get("color_order")) ||
                !"stored".equals(settings.get("orientation")) ||
                !"nearest".equals(settings.get("interpolation")) ||
                !"stretch".equals(settings.get("resize"))) throw new IllegalArgumentException("imageContract");
        long channels = shape["NCHW".equals(layout) ? 1 : 3];
        long height = shape["NCHW".equals(layout) ? 2 : 1];
        long width = shape["NCHW".equals(layout) ? 3 : 2];
        if (channels != 3 || height <= 0 || width <= 0 || width > Integer.MAX_VALUE ||
                height > Integer.MAX_VALUE || height > budget / 24 / width)
            throw new IllegalArgumentException("imageBudget"); // HC-078: tensor plus bitmap copies.
        double scale = ((Number)settings.get("scale")).doubleValue();
        List<?> mean = (List<?>)settings.get("mean"), std = (List<?>)settings.get("std");
        if (!Double.isFinite(scale) || scale <= 0 || mean.size()!=3 || std.size()!=3)
            throw new IllegalArgumentException("imageNormalization");
        double[] means = new double[3], deviations = new double[3];
        for (int c=0;c<3;c++) {
            means[c]=((Number)mean.get(c)).doubleValue(); deviations[c]=((Number)std.get(c)).doubleValue();
            if (!Double.isFinite(means[c]) || !Double.isFinite(deviations[c]) || deviations[c]<=0)
                throw new IllegalArgumentException("imageNormalization");
        }
        BitmapFactory.Options options = new BitmapFactory.Options(); options.inJustDecodeBounds=true;
        BitmapFactory.decodeFile(file.getPath(),options);
        if (options.outWidth<=0 || options.outHeight<=0 ||
                options.outHeight > budget / 8 / options.outWidth ||
                !("image/png".equals(options.outMimeType) || "image/jpeg".equals(options.outMimeType)))
            throw new IllegalArgumentException("imageFormatOrBudget");
        options.inJustDecodeBounds=false; options.inPreferredConfig=Bitmap.Config.ARGB_8888;
        options.inScaled=false;
        control.check();
        Bitmap source=BitmapFactory.decodeFile(file.getPath(),options);
        if(source==null) throw new IllegalArgumentException("imageDecode");
        Bitmap resized=null;
        try {
            control.check();
            resized=Bitmap.createScaledBitmap(source,(int)width,(int)height,false);
            float[] tensor=new float[(int)(width*height*3)];
            int[] row=new int[(int)width];
            for(int y=0;y<height;y++) {
                control.check(); resized.getPixels(row,0,(int)width,0,y,(int)width,1);
                for(int x=0;x<width;x++) {
                    if ((row[x]>>>24)!=255) throw new IllegalArgumentException("imageTransparencyUnsupported");
                    for(int c=0;c<3;c++) {
                        int pixel=(row[x] >>> (16-c*8)) & 255;
                        int index="NCHW".equals(layout) ? (int)((c*height+y)*width+x) : (int)((y*width+x)*3+c);
                        tensor[index]=(float)((pixel*scale-means[c])/deviations[c]);
                        if(!Float.isFinite(tensor[index])) throw new IllegalArgumentException("imageNonFinite");
                    }
                }
            }
            return tensor;
        } finally {if(resized!=null && resized!=source)resized.recycle(); source.recycle();}
    }
}
