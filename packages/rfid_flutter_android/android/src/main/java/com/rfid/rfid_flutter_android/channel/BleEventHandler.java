package com.rfid.rfid_flutter_android.channel;

import android.content.Context;

import io.flutter.plugin.common.EventChannel;

public class BleEventHandler implements EventChannel.StreamHandler {
    private final BleTray tray;

    public BleEventHandler(Context context) {
        tray = BleTray.get(context);
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        tray.setSink(events);
    }

    @Override
    public void onCancel(Object arguments) {
        tray.setSink(null);
    }
}
