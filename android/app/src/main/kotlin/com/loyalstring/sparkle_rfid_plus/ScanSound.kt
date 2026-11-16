package com.loyalstring.sparkle_rfid_plus

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Same tones as Sparkle RFID: inventory loops barcodebeep, a match beeps,
/// and search picks fourty / sixty / found2 / barcodebeep from the RSSI.
class ScanSound(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "com.loyalstring.sparkle_rfid_plus/scan_sound")
    private var pool: SoundPool? = null
    private val sounds = HashMap<Int, Int>()
    private var inventoryPlayer: MediaPlayer? = null
    private var audioManager: AudioManager? = null
    private var streamId = 0
    private var loadsFinished = 0
    private var pendingId = 0
    private var pendingLoop = 0

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startInventorySound" -> {
                    ensurePool()
                    startInventoryLoop()
                    result.success(null)
                }
                "stopInventorySound" -> {
                    stopInventoryLoop()
                    result.success(null)
                }
                "playBeep" -> {
                    play(1, 0)
                    result.success(null)
                }
                "playSound" -> {
                    val id = call.argument<Int>("id") ?: 1
                    val loop = call.argument<Int>("loop") ?: 0
                    play(id, loop)
                    result.success(null)
                }
                "stopSound" -> {
                    stopTone()
                    result.success(null)
                }
                "stopAll" -> {
                    stopAll()
                    result.success(null)
                }
                "prepare" -> {
                    ensurePool()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startInventoryLoop() {
        try {
            if (inventoryPlayer == null) {
                val resId = context.resources.getIdentifier("barcodebeep", "raw", context.packageName)
                if (resId == 0) return
                inventoryPlayer = MediaPlayer.create(context, resId)
                inventoryPlayer?.isLooping = true
            }
            if (inventoryPlayer?.isPlaying != true) {
                inventoryPlayer?.start()
            }
        } catch (_: Throwable) {
        }
    }

    private fun stopInventoryLoop() {
        try {
            inventoryPlayer?.stop()
            inventoryPlayer?.release()
        } catch (_: Throwable) {
        }
        inventoryPlayer = null
    }

    private fun ensurePool() {
        if (pool != null) return
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder()
            .setMaxStreams(10)
            .setAudioAttributes(attributes)
            .build()
        pool?.setOnLoadCompleteListener { _, _, _ ->
            loadsFinished += 1
            if (loadsFinished >= 5 && pendingId > 0) {
                val id = pendingId
                val loop = pendingLoop
                pendingId = 0
                playNow(id, loop)
            }
        }
        sounds[1] = load("barcodebeep")
        sounds[2] = load("sixty")
        sounds[3] = load("seventy")
        sounds[4] = load("fourty")
        sounds[5] = load("found2")
    }

    private fun load(name: String): Int {
        val resId = context.resources.getIdentifier(name, "raw", context.packageName)
        if (resId == 0) return 0
        return pool?.load(context, resId, 1) ?: 0
    }

    private fun play(id: Int, loop: Int) {
        try {
            ensurePool()
            if (loadsFinished < 5) {
                pendingId = id
                pendingLoop = loop
                return
            }
            playNow(id, loop)
        } catch (_: Throwable) {
        }
    }

    private fun playNow(id: Int, loop: Int) {
        val soundId = sounds[id] ?: return
        if (soundId == 0) return
        val max = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
        val current = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
        val volume = if (max > 0f) current / max else 1f
        if (streamId != 0) pool?.stop(streamId)
        streamId = pool?.play(soundId, volume, volume, 1, loop, 1f) ?: 0
    }

    private fun stopTone() {
        pendingId = 0
        try {
            if (streamId != 0) pool?.stop(streamId)
        } catch (_: Throwable) {
        }
        streamId = 0
    }

    private fun stopAll() {
        stopInventoryLoop()
        stopTone()
    }
}
