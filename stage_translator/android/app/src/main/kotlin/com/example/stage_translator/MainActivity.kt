package com.example.stage_translator

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
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
    }
}
