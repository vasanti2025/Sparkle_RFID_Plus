package com.rfid.rfid_flutter_android.channel;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.util.Log;

import androidx.annotation.NonNull;

import com.rscja.barcode.BarcodeDecoder;
import com.rscja.barcode.BarcodeFactory;
import com.rscja.scanner.utility.ScannerUtility;
import com.rscja.team.qcom.utility.LogUtility_qcom;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class BarcodeChannelHandler implements MethodChannel.MethodCallHandler {
    private static final String TAG = "UART";

    private final Context context;
    private final ExecutorService executor;

    private BarcodeDecoder mReader;

    public BarcodeChannelHandler(Context context, ExecutorService executor) {
        this.context = context;
        this.executor = executor;
    }

    // 方法处理器映射表
    private final Map<String, MethodHandler> methodHandlers = new HashMap<String, MethodHandler>() {{
        // 基础操作
        put("init", BarcodeChannelHandler.this::init);
        put("free", BarcodeChannelHandler.this::free);
        put("isInitialized", BarcodeChannelHandler.this::isInitialized);

        // 扫描操作
        put("startScan", BarcodeChannelHandler.this::startScan);
        put("stopScan", BarcodeChannelHandler.this::stopScan);
        put("setTimeout", BarcodeChannelHandler.this::setTimeout);

    }};

    @Override
    public void onMethodCall(@NonNull MethodCall methodCall, @NonNull MethodChannel.Result result) {
        executor.execute(() -> {
            try {
                if (!methodCall.method.equals("init")
                        && !methodCall.method.equals("free")
                        && (mReader == null || !mReader.isOpen())
                ) {
                    result.error(TAG, "Not initialized", "");
                    return;
                }
                LogUtility_qcom.myLogInfo(TAG, "Method: " + methodCall.method + " with args: " + methodCall.arguments);

                MethodHandler handler = methodHandlers.get(methodCall.method);
                if (handler != null) {
                    handler.handle(methodCall, result);
                } else {
                    result.notImplemented();
                }
            } catch (Exception e) {
                // handler.post(() -> result.error(TAG, "Error: " + e.getMessage(), null));
                result.error(TAG, "Error: " + e.getMessage(), null);
                e.printStackTrace();
            }
        });
    }

    private void init(MethodCall methodCall, MethodChannel.Result result) {
        try {
            PackageManager pm = context.getPackageManager();
            List<PackageInfo> packages = pm.getInstalledPackages(0);
            for (PackageInfo packageInfo : packages) {
                if (packageInfo.packageName.contains("com.rscja.scanner")) {
                    // 找到匹配的应用
                    Log.d("PackageFinder", "Found package: " + packageInfo.packageName);
                    ScannerUtility.getScannerInerface().setScannerPackageName(packageInfo.packageName);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
            Log.e("PackageFinder", e.toString());
        }
        mReader = BarcodeFactory.getInstance().getBarcodeDecoder();
        result.success(mReader.open(context));
    }

    private void free(MethodCall methodCall, MethodChannel.Result result) {
        if (mReader == null) {
            result.success(true);
            return;
        }
        mReader.close();
        result.success(true);
        mReader = null;
    }

    private void isInitialized(MethodCall methodCall, MethodChannel.Result result) {
        result.success(mReader != null && mReader.isOpen());
    }

    private void startScan(MethodCall methodCall, MethodChannel.Result result) {
        result.success(mReader.startScan());
    }

    private void stopScan(MethodCall methodCall, MethodChannel.Result result) {
        mReader.stopScan();
        result.success(true);
    }

    private void setTimeout(MethodCall methodCall, MethodChannel.Result result) {
        mReader.setTimeOut(methodCall.argument("value"));
        result.success(true);
    }

}
