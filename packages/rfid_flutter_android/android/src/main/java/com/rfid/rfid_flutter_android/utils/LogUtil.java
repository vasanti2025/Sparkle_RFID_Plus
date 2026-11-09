package com.rfid.rfid_flutter_android.utils;

import android.util.Log;

/**
 * 简化的日志工具类
 */
public class LogUtil {

    private static final String DEFAULT_TAG = "RfidFlutter";
    private static boolean isDebugEnabled = true;

    /**
     * 设置调试模式
     * @param debug 是否启用调试日志
     */
    public static void setDebug(boolean debug) {
        isDebugEnabled = debug;
    }

    /**
     * 获取当前调试模式状态
     * @return 是否启用调试日志
     */
    public static boolean isDebug() {
        return isDebugEnabled;
    }

    /**
     * Verbose级别日志
     */
    public static void v(String tag, String msg) {
        if (isDebugEnabled) {
            Log.v(formatTag(tag), msg);
        }
    }

    /**
     * Debug级别日志
     */
    public static void d(String tag, String msg) {
        if (isDebugEnabled) {
            Log.d(formatTag(tag), msg);
        }
    }

    /**
     * Info级别日志
     */
    public static void i(String tag, String msg) {
        if (isDebugEnabled) {
            Log.i(formatTag(tag), msg);
        }
    }

    /**
     * Warning级别日志
     */
    public static void w(String tag, String msg) {
        if (isDebugEnabled) {
            Log.w(formatTag(tag), msg);
        }
    }

    /**
     * Warning级别日志（带异常）
     */
    public static void w(String tag, String msg, Throwable tr) {
        if (isDebugEnabled) {
            Log.w(formatTag(tag), msg, tr);
        }
    }

    /**
     * Error级别日志
     */
    public static void e(String tag, String msg) {
        // Error日志总是输出，不受debug开关影响
        Log.e(formatTag(tag), msg);
    }

    /**
     * Error级别日志（带异常）
     */
    public static void e(String tag, String msg, Throwable tr) {
        // Error日志总是输出，不受debug开关影响
        Log.e(formatTag(tag), msg, tr);
    }

    /**
     * 格式化标签，提供统一的日志格式
     */
    private static String formatTag(String tag) {
        if (tag == null || tag.trim().isEmpty()) {
            return DEFAULT_TAG;
        }
        return DEFAULT_TAG + "-" + tag;
    }

    // 便捷方法：使用默认标签
    public static void v(String msg) {
        v(DEFAULT_TAG, msg);
    }

    public static void d(String msg) {
        d(DEFAULT_TAG, msg);
    }

    public static void i(String msg) {
        i(DEFAULT_TAG, msg);
    }

    public static void w(String msg) {
        w(DEFAULT_TAG, msg);
    }

    public static void e(String msg) {
        e(DEFAULT_TAG, msg);
    }

    public static void e(String msg, Throwable tr) {
        e(DEFAULT_TAG, msg, tr);
    }
}

