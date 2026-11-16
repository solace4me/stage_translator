package com.example.stage_translator

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Sound outputs that mean "not the phone's own speaker": cable, USB,
    // Bluetooth speaker or headphones, HDMI. The pad uses its deep version there.
    private val externalOutputs = setOf(
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_AUX_LINE,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_HDMI,
        26, // TYPE_BLE_HEADSET (Android 12+)
        27, // TYPE_BLE_SPEAKER (Android 12+)
    )

    // A hymn file sent to the app from another app ("Open with" / "Share"),
    // e.g. a MusicXML export from a sheet-music scanner. Held until Flutter asks.
    private var filesChannel: MethodChannel? = null
    private var pendingFile: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stage_translator/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "outputIsPhoneSpeaker") {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val outputs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    result.success(outputs.none { it.type in externalOutputs })
                } else {
                    result.notImplemented()
                }
            }

        filesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stage_translator/files")
        filesChannel?.setMethodCallHandler { call, result ->
            if (call.method == "takeIncomingFile") {
                result.success(pendingFile)
                pendingFile = null
            } else {
                result.notImplemented()
            }
        }
        readIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (readIncoming(intent)) filesChannel?.invokeMethod("incomingFile", null)
    }

    /** Reads the file an "Open with" / "Share" intent points at. True if there was one. */
    private fun readIncoming(intent: Intent?): Boolean {
        if (intent == null) return false
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return false
        return try {
            var name = uri.lastPathSegment ?: "file"
            if (uri.scheme == "content") {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
                }
            }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(64 * 1024)
                var total = 0
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > 30 * 1024 * 1024) return false // not a hymn file
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            } ?: return false
            pendingFile = mapOf("name" to name, "bytes" to bytes)
            true
        } catch (e: Exception) {
            false
        }
    }
}
