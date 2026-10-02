package com.ifallmusic.app

import android.content.Context

/**
 * Counts cold starts that never reached the first Flutter frame.
 * Three unfinished launches put the next start into safe mode.
 */
object SaxifyBoot {
    private const val PREFS = "saxify_boot"
    private const val KEY_FAILS = "fails"
    private var noted = false

    fun noteLaunch(context: Context) {
        if (noted) return
        noted = true
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getInt(KEY_FAILS, 0)
        prefs.edit().putInt(KEY_FAILS, previous + 1).apply()
    }

    fun snapshot(context: Context): Map<String, Any> {
        val fails = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_FAILS, 0)
        return mapOf(
            "safeMode" to (fails >= 3),
            "fails" to fails,
            "sdk" to android.os.Build.VERSION.SDK_INT,
        )
    }

    fun markSuccess(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_FAILS, 0)
            .apply()
    }

    fun reset(context: Context) {
        markSuccess(context)
    }
}
