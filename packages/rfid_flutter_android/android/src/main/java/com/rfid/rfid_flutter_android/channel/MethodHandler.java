package com.rfid.rfid_flutter_android.channel;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

@FunctionalInterface
public interface MethodHandler {
    void handle(MethodCall methodCall, MethodChannel.Result result);
}