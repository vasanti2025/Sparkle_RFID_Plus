package com.rfid.rfid_flutter_android;

import android.app.Activity;
import android.content.Context;

import androidx.annotation.NonNull;

import com.rfid.rfid_flutter_android.channel.BarcodeChannelHandler;
import com.rfid.rfid_flutter_android.channel.BarcodeEventHandler;
import com.rfid.rfid_flutter_android.channel.DeviceInfoChannelHandler;
import com.rfid.rfid_flutter_android.channel.UARTChannelHandler;
import com.rfid.rfid_flutter_android.channel.UARTEventHandler;
import com.rfid.rfid_flutter_android.channel.URA4ChannelHandler;
import com.rfid.rfid_flutter_android.channel.URA4EventHandler;
import com.rfid.rfid_flutter_android.channel.WindowEventHandler;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class RfidFlutterAndroidPlugin implements FlutterPlugin, ActivityAware {
    private static final String TAG = "RfidFlutter";

    private Context context;
    private WindowEventHandler windowEventHandler;

    private ExecutorService executor;

    // 插件初始化
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        executor = Executors.newCachedThreadPool();

        MethodChannel channelURAT = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/uart");
        channelURAT.setMethodCallHandler(new UARTChannelHandler(context, executor));
        EventChannel uartEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/uartEvent");
        uartEventChannel.setStreamHandler(new UARTEventHandler());


        MethodChannel channelURA4 = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/ura4");
        channelURA4.setMethodCallHandler(new URA4ChannelHandler(context, executor));
        EventChannel ura4eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/ura4Event");
        ura4eventChannel.setStreamHandler(new URA4EventHandler());


        MethodChannel channelBarcode = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/barcode");
        channelBarcode.setMethodCallHandler(new BarcodeChannelHandler(context, executor));
        EventChannel barcodeEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/barcodeEvent");
        barcodeEventChannel.setStreamHandler(new BarcodeEventHandler());


        MethodChannel channelDeviceInfo = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/deviceInfo");
        channelDeviceInfo.setMethodCallHandler(new DeviceInfoChannelHandler(context, executor));

        windowEventHandler = new WindowEventHandler();
        EventChannel windowEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "rfid_flutter_android/windowEvent");
        windowEventChannel.setStreamHandler(windowEventHandler);

    }

    // 插件卸载
    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        context = null;
        executor.shutdown();
        executor = null;
    }


    // *************** ActivityAware接口实现 ***************

    private Activity activity;

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding activityPluginBinding) {
        activity = activityPluginBinding.getActivity();
        if (windowEventHandler != null) {
            windowEventHandler.setWindowCallback(activity.getWindow().getCallback());
            activity.getWindow().setCallback(windowEventHandler);
        }
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding activityPluginBinding) {
        activity = activityPluginBinding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }
}
