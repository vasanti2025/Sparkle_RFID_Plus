package com.rfid.rfid_flutter_android.channel;

import android.os.Handler;
import android.os.Looper;

import com.rfid.rfid_flutter_android.utils.TagUtil;
import com.rscja.barcode.BarcodeFactory;
import com.rscja.deviceapi.entity.BarcodeEntity;

import io.flutter.plugin.common.EventChannel;

public class BarcodeEventHandler implements EventChannel.StreamHandler {
    private EventChannel.EventSink eventSink;
    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        this.eventSink = eventSink;
        BarcodeFactory.getInstance().getBarcodeDecoder().setDecodeCallback((BarcodeEntity barcodeEntity) -> {
            if (barcodeEntity != null && this.eventSink != null) {
                handler.post(() -> this.eventSink.success(TagUtil.getBarcodeMap(barcodeEntity)));
            }
        });
    }

    @Override
    public void onCancel(Object o) {
        BarcodeFactory.getInstance().getBarcodeDecoder().setDecodeCallback(null);
        this.eventSink = null;
    }
}
