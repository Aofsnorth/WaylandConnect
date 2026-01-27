package com.arthenyx.wayland_connect_app

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.arthenyx.wayland_connect/volume"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            methodChannel?.invokeMethod("volume_up", null)
            return true
        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            methodChannel?.invokeMethod("volume_down", null)
            return true
        } else if (keyCode == KeyEvent.KEYCODE_POWER) {
            // Attempt to intercept Power Button
            methodChannel?.invokeMethod("power_down", null)
            return true 
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_POWER) {
             methodChannel?.invokeMethod("power_up", null)
             return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
