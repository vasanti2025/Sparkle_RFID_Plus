package com.rfid.rfid_flutter_android.channel;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.core.content.ContextCompat;

import com.rfid.rfid_flutter_android.utils.TagUtil;
import com.rscja.deviceapi.RFIDWithUHFBLE;
import com.rscja.deviceapi.entity.InventoryModeEntity;
import com.rscja.deviceapi.entity.UHFTAGInfo;
import com.rscja.deviceapi.interfaces.ConnectionStatus;
import com.rscja.deviceapi.interfaces.ConnectionStatusCallback;
import com.rscja.deviceapi.interfaces.IUHFInventoryCallback;
import com.rscja.deviceapi.interfaces.ScanBTCallback;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import io.flutter.plugin.common.EventChannel;

/**
 * Chainway Bluetooth tray (RFIDWithUHFBLE), the same DeviceAPI used by the
 * handheld UART reader. Tags are delivered on the BLE event channel.
 */
public class BleTray {
    private static BleTray instance;

    private final Context context;
    private RFIDWithUHFBLE reader;
    private boolean initialized;
    private volatile boolean connected;
    private volatile boolean connecting;
    private String address = "";
    private EventChannel.EventSink sink;
    private final AtomicReference<CountDownLatch> connectLatch = new AtomicReference<>();

    private final ConnectionStatusCallback<Object> statusCallback = new ConnectionStatusCallback<Object>() {
        @Override
        public void getStatus(ConnectionStatus status, Object device) {
            if (status == ConnectionStatus.CONNECTED) {
                connecting = false;
                connected = true;
                CountDownLatch latch = connectLatch.get();
                if (latch != null) latch.countDown();
            } else if (status == ConnectionStatus.CONNECTING) {
                connecting = true;
            } else if (status == ConnectionStatus.DISCONNECTED) {
                connected = false;
                if (connecting) {
                    connecting = false;
                    CountDownLatch latch = connectLatch.get();
                    if (latch != null) latch.countDown();
                }
            }
        }
    };

    private final IUHFInventoryCallback inventoryCallback = uhftagInfo -> {
        EventChannel.EventSink current = sink;
        if (uhftagInfo == null || current == null) return;
        Map<String, Object> map = TagUtil.getTagMap(uhftagInfo);
        android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());
        handler.post(() -> {
            EventChannel.EventSink live = sink;
            if (live != null) live.success(map);
        });
    };

    private BleTray(Context context) {
        this.context = context.getApplicationContext();
    }

    public static synchronized BleTray get(Context context) {
        if (instance == null) instance = new BleTray(context);
        return instance;
    }

    public void setSink(EventChannel.EventSink sink) {
        this.sink = sink;
        if (reader != null) reader.setInventoryCallback(inventoryCallback);
    }

    public boolean init() {
        try {
            if (reader == null) reader = RFIDWithUHFBLE.getInstance();
            reader.setInventoryCallback(inventoryCallback);
            reader.setConnectionStatusCallback(statusCallback);
            if (!initialized) {
                if (Looper.myLooper() == Looper.getMainLooper()) {
                    initialized = reader.init(context);
                } else {
                    java.util.concurrent.atomic.AtomicBoolean ok = new java.util.concurrent.atomic.AtomicBoolean(false);
                    CountDownLatch latch = new CountDownLatch(1);
                    new Handler(Looper.getMainLooper()).post(() -> {
                        try {
                            ok.set(reader.init(context));
                        } catch (Throwable ignored) {
                        }
                        latch.countDown();
                    });
                    latch.await(5, TimeUnit.SECONDS);
                    initialized = ok.get();
                }
            }
            if (initialized) {
                try {
                    reader.setSupportRssi(true);
                } catch (Throwable ignored) {
                }
            }
            return initialized;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public List<Map<String, String>> connectedDevices() {
        LinkedHashMap<String, String> found = new LinkedHashMap<>();
        if (!hasConnectPermission()) return new ArrayList<>();
        try {
            BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            if (manager != null) {
                try {
                    for (BluetoothDevice device : manager.getConnectedDevices(BluetoothProfile.GATT)) {
                        add(found, device);
                    }
                } catch (Throwable ignored) {
                }
                try {
                    for (BluetoothDevice device : manager.getConnectedDevices(BluetoothProfile.GATT_SERVER)) {
                        add(found, device);
                    }
                } catch (Throwable ignored) {
                }
            }
            BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
            if (adapter != null && adapter.isEnabled()) {
                for (BluetoothDevice device : adapter.getBondedDevices()) {
                    if (isSystemConnected(device)) add(found, device);
                }
            }
        } catch (Throwable ignored) {
        }
        List<Map<String, String>> rows = new ArrayList<>();
        for (Map.Entry<String, String> entry : found.entrySet()) {
            Map<String, String> row = new HashMap<>();
            row.put("name", entry.getValue());
            row.put("address", entry.getKey());
            rows.add(row);
        }
        return rows;
    }

    /** Paired devices, including a tray Android has not marked connected yet. */
    public List<Map<String, String>> bondedDevices() {
        LinkedHashMap<String, String> found = new LinkedHashMap<>();
        if (!hasConnectPermission()) return new ArrayList<>();
        try {
            BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
            if (adapter != null && adapter.isEnabled()) {
                for (BluetoothDevice device : adapter.getBondedDevices()) {
                    add(found, device);
                }
            }
        } catch (Throwable ignored) {
        }
        List<Map<String, String>> rows = new ArrayList<>();
        for (Map.Entry<String, String> entry : found.entrySet()) {
            Map<String, String> row = new HashMap<>();
            row.put("name", entry.getValue());
            row.put("address", entry.getKey());
            rows.add(row);
        }
        return rows;
    }

    public boolean connectAndWait(String mac, long timeoutMs) {
        if (mac == null || mac.trim().isEmpty()) return false;
        String target = mac.trim();
        if (isReallyConnected() && target.equalsIgnoreCase(address)) return true;
        if (!init()) return false;
        boolean osHeld = isSystemConnected(target);
        if (!osHeld) preScan(target, 2500L);
        if (handshake(target, osHeld ? Math.min(Math.max(1000L, timeoutMs), 8000L) : Math.max(1000L, timeoutMs))) {
            return true;
        }
        if (isSystemConnected(target) || sdkConnected()) {
            address = target;
            connected = true;
            connecting = false;
            return true;
        }
        return false;
    }

    public boolean startInventory() {
        try {
            if (reader == null || !init()) return false;
            reader.setInventoryCallback(inventoryCallback);
            drain();
            if (reader.startInventoryTag()) return true;
            SystemClock.sleep(400);
            return reader.startInventoryTag();
        } catch (Throwable ignored) {
            return false;
        }
    }

    public boolean stopInventory() {
        try {
            if (reader == null) return true;
            return reader.stopInventory();
        } catch (Throwable ignored) {
            return false;
        }
    }

    public boolean setPower(int power) {
        try {
            return reader != null && reader.setPower(power);
        } catch (Throwable ignored) {
            return false;
        }
    }

    public boolean setInventoryMode(int bank, int offset, int length) {
        try {
            if (reader == null) return false;
            if (bank != InventoryModeEntity.MODE_EPC
                    && bank != InventoryModeEntity.MODE_EPC_TID
                    && bank != InventoryModeEntity.MODE_EPC_TID_USER
                    && bank != InventoryModeEntity.MODE_EPC_TID_RESERVED
                    && bank != InventoryModeEntity.MODE_EPC_RESERVED
                    && bank != InventoryModeEntity.MODE_TEMPERATURE_TAG
                    && bank != InventoryModeEntity.MODE_LED_TAG) {
                return false;
            }
            InventoryModeEntity.Builder builder = new InventoryModeEntity.Builder().setMode(bank);
            if (bank == InventoryModeEntity.MODE_EPC_TID_USER) {
                builder.setUserOffset(offset).setUserLength(length);
            } else if (bank == InventoryModeEntity.MODE_EPC_TID_RESERVED || bank == InventoryModeEntity.MODE_EPC_RESERVED) {
                builder.setReservedOffset(offset).setReservedLength(length);
            }
            return reader.setEPCAndTIDUserMode(builder.build());
        } catch (Throwable ignored) {
            return false;
        }
    }

    public boolean isReallyConnected() {
        if (connected || sdkConnected()) return true;
        return !address.isEmpty() && isSystemConnected(address);
    }

    public boolean hasConnectPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
        }
        return ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean handshake(String target, long timeoutMs) {
        address = target;
        connecting = true;
        connected = false;
        CountDownLatch latch = new CountDownLatch(1);
        connectLatch.set(latch);
        try {
            reader.connect(target, statusCallback);
        } catch (Throwable ignored) {
            connecting = false;
            return isSystemConnected(target) || sdkConnected();
        }
        long deadline = SystemClock.elapsedRealtime() + timeoutMs;
        while (SystemClock.elapsedRealtime() < deadline) {
            if (connected || sdkConnected()) return true;
            try {
                latch.await(300L, TimeUnit.MILLISECONDS);
            } catch (InterruptedException ignored) {
                break;
            }
        }
        if (connected || sdkConnected() || isSystemConnected(target)) {
            connected = true;
            connecting = false;
            return true;
        }
        connecting = false;
        return false;
    }

    private void preScan(String target, long maxMs) {
        if (reader == null || !hasScanPermission()) return;
        CountDownLatch found = new CountDownLatch(1);
        try {
            reader.stopScanBTDevices();
        } catch (Throwable ignored) {
        }
        try {
            ScanBTCallback callback = (device, rssi, data) -> {
                if (device != null && target.equalsIgnoreCase(device.getAddress())) {
                    found.countDown();
                }
            };
            reader.startScanBTDevices(callback);
            found.await(maxMs, TimeUnit.MILLISECONDS);
        } catch (Throwable ignored) {
        } finally {
            try {
                reader.stopScanBTDevices();
            } catch (Throwable ignored) {
            }
        }
    }

    private boolean sdkConnected() {
        try {
            if (reader != null && reader.getConnectStatus() == ConnectionStatus.CONNECTED) {
                connected = true;
                connecting = false;
                return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private boolean hasScanPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
        }
        return ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void drain() {
        if (reader == null) return;
        for (int i = 0; i < 64; i++) {
            UHFTAGInfo tag;
            try {
                tag = reader.readTagFromBuffer();
            } catch (Throwable ignored) {
                break;
            }
            if (tag == null || tag.getEPC() == null || tag.getEPC().isEmpty()) break;
        }
    }

    private void add(Map<String, String> found, BluetoothDevice device) {
        if (device == null) return;
        String mac = device.getAddress() == null ? "" : device.getAddress().trim();
        if (mac.isEmpty()) return;
        String name;
        try {
            name = device.getName();
        } catch (SecurityException ignored) {
            name = null;
        }
        if (name == null || name.trim().isEmpty()) name = "Bluetooth Device";
        String existing = found.get(mac);
        if (existing == null || existing.equals("Bluetooth Device")) found.put(mac, name.trim());
    }

    private boolean isSystemConnected(BluetoothDevice device) {
        try {
            Object value = device.getClass().getMethod("isConnected").invoke(device);
            return value instanceof Boolean && (Boolean) value;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private boolean isSystemConnected(String mac) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) return false;
        try {
            for (BluetoothDevice device : adapter.getBondedDevices()) {
                if (device.getAddress() != null && device.getAddress().equalsIgnoreCase(mac)) {
                    return isSystemConnected(device);
                }
            }
        } catch (Throwable ignored) {
            return false;
        }
        return false;
    }
}
