package com.ifallmusic.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the most recent deep link (an `ifallmusic://party/…` or an
 * `https://party.ifallmusic.app/invite/…` tap) until the Dart side is
 * ready to read it. On a warm start the link is also pushed straight to
 * Dart as an `onDeepLink` call.
 */
object DeepLinkInbox {
    @Volatile
    var pending: String? = null

    @Volatile
    var channel: MethodChannel? = null

    fun offer(link: String) {
        pending = link
        try {
            channel?.invokeMethod("onDeepLink", link)
        } catch (_: Exception) {
            // The engine may still be starting; Dart pulls via takeDeepLink.
        }
    }

    fun take(): String? {
        val value = pending
        pending = null
        return value
    }
}

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        SaxifyBoot.noteLaunch(this)
        super.onCreate(savedInstanceState)
        applyHighestRefreshRate()
        intent?.dataString?.let { DeepLinkInbox.pending = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let { DeepLinkInbox.offer(it) }
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
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ifallmusic.app/bridge",
        )
        channel.setMethodCallHandler { call, result -> bridge.handle(call, result) }
        DeepLinkInbox.channel = channel
    }
}
