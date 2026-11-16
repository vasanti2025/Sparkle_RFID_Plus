package com.loyalstring.sparkle_rfid_plus

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ScanSound(this, flutterEngine.dartExecutor.binaryMessenger).attach()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.loyalstring.sparkle_rfid_plus/permissions",
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestScanPermissions") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val missing = scanPermissions.filter { permission ->
                ContextCompat.checkSelfPermission(this, permission) !=
                    PackageManager.PERMISSION_GRANTED
            }
            if (missing.isEmpty()) {
                result.success(true)
                return@setMethodCallHandler
            }
            pendingPermission?.success(false)
            pendingPermission = result
            requestPermissions(missing.toTypedArray(), scanPermissionRequest)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != scanPermissionRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private companion object {
        const val scanPermissionRequest = 4101
        val scanPermissions = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
    }
}
