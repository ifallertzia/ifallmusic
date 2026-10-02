package com.ifallmusic.app

import android.content.Context
import android.os.Build
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        SaxifyBoot.noteLaunch(this)
        super.onCreate(savedInstanceState)
        applyHighestRefreshRate()
    }

    // Flutter renders at whatever the panel offers. Phones that ship with a
    // 90/120/144 Hz screen default to 60 Hz unless the window asks for the
    // faster mode, so every animation looks heavier than it should.
    private fun applyHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val windowManager =
            getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        val display = windowManager.defaultDisplay ?: return
        val best = display.supportedModes.maxByOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        if (attributes.preferredDisplayModeId == best.modeId) return
        attributes.preferredDisplayModeId = best.modeId
        window.attributes = attributes
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SaxifyBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ifallmusic.app/bridge")
            .setMethodCallHandler { call, result -> bridge.handle(call, result) }
    }
}
