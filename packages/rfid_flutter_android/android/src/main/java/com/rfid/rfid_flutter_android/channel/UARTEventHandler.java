package com.rfid.rfid_flutter_android.channel;

import android.os.Handler;
import android.os.Looper;

import com.rfid.rfid_flutter_android.utils.TagUtil;
import com.rscja.deviceapi.RFIDWithUHFUART;
import com.rscja.deviceapi.entity.UHFTAGInfo;
import com.rscja.deviceapi.exception.ConfigurationException;
import com.rscja.team.qcom.utility.LogUtility_qcom;

import io.flutter.plugin.common.EventChannel;

public class UARTEventHandler implements EventChannel.StreamHandler {
    private EventChannel.EventSink eventSink;
    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        this.eventSink = eventSink;
        try {
            RFIDWithUHFUART.getInstance().setInventoryCallback((UHFTAGInfo uhftagInfo) -> {
                if (uhftagInfo != null && this.eventSink != null) {
                    //LogUtility_qcom.myLogV("UART", "TAG EPC " + uhftagInfo.getEPC());
                    handler.post(() -> this.eventSink.success(TagUtil.getTagMap(uhftagInfo)));
                }
            });

        } catch (ConfigurationException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public void onCancel(Object o) {
        try {
            RFIDWithUHFUART.getInstance().setInventoryCallback(null);
        } catch (ConfigurationException e) {
            LogUtility_qcom.myLogErr("UART", "onCancel " + e.getMessage());
        }
        this.eventSink = null;
    }
}
