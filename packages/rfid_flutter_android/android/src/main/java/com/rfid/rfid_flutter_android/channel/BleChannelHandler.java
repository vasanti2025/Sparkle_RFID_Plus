package com.rfid.rfid_flutter_android.channel;

import android.app.Activity;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;

import java.util.concurrent.ExecutorService;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class BleChannelHandler implements MethodChannel.MethodCallHandler {
    private final BleTray tray;
    private final ExecutorService executor;
    private Activity activity;

    public BleChannelHandler(android.content.Context context, ExecutorService executor) {
        this.tray = BleTray.get(context);
        this.executor = executor;
    }

    public void setActivity(Activity activity) {
        this.activity = activity;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        executor.execute(() -> {
            try {
                switch (call.method) {
                    case "listConnected":
                        if (!tray.hasConnectPermission()) requestPermission();
                        finish(result, tray.connectedDevices());
                        break;
                    case "bondedDevices":
                        if (!tray.hasConnectPermission()) requestPermission();
                        finish(result, tray.bondedDevices());
                        break;
                    case "hasPermission":
                        finish(result, tray.hasConnectPermission());
                        break;
                    case "requestPermission":
                        requestPermission();
                        finish(result, tray.hasConnectPermission());
                        break;
                    case "connect":
                        String address = call.argument("address");
                        Integer timeout = call.argument("timeoutMs");
                        finish(result, tray.connectAndWait(address, timeout == null ? 8000L : timeout.longValue()));
                        break;
                    case "startInventory":
                        finish(result, tray.startInventory());
                        break;
                    case "stopInventory":
                        finish(result, tray.stopInventory());
                        break;
                    case "setPower":
                        Integer power = call.argument("value");
                        finish(result, power != null && tray.setPower(power));
                        break;
                    case "setInventoryMode":
                        Integer bank = call.argument("inventoryBank");
                        Integer offset = call.argument("offset");
                        Integer length = call.argument("length");
                        finish(result, tray.setInventoryMode(
                                bank == null ? 0 : bank,
                                offset == null ? 0 : offset,
                                length == null ? 0 : length));
                        break;
                    case "isConnected":
                        finish(result, tray.isReallyConnected());
                        break;
                    default:
                        runOnMain(() -> result.notImplemented());
                        break;
                }
            } catch (Exception error) {
                runOnMain(() -> result.error("ble", error.getMessage(), null));
            }
        });
    }

    private void finish(MethodChannel.Result result, Object value) {
        runOnMain(() -> result.success(value));
    }

    private void runOnMain(Runnable action) {
        Activity current = activity;
        if (current != null) {
            current.runOnUiThread(action);
            return;
        }
        new Handler(Looper.getMainLooper()).post(action);
    }

    private void requestPermission() {
        Activity current = activity;
        if (current == null) return;
        current.runOnUiThread(() -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ActivityCompat.requestPermissions(current, new String[]{
                        android.Manifest.permission.BLUETOOTH_CONNECT,
                        android.Manifest.permission.BLUETOOTH_SCAN,
                }, 2401);
            } else {
                ActivityCompat.requestPermissions(current, new String[]{
                        android.Manifest.permission.BLUETOOTH,
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                }, 2401);
            }
        });
    }
}
