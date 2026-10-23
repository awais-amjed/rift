package com.codingfries.rift

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Why the app's last few runs ended, as Android kept it (Android 11 and up).
 *
 * A run killed for memory, stopped for an ANR or ended by a native crash
 * leaves nothing in its own log, and on a phone the first is the usual one:
 * a call's foreground service killed in the background looks exactly like a
 * crash to the person it happened to. Android records each ending for the
 * app to read back, with no permission, so Dart writes the recent ones into
 * the next session's log (`AppExitReasons`), which a bug report carries.
 *
 * Only the fields go across; the trace an ANR or native crash carries is
 * left behind, since the crash handler in the Rust library has already
 * written the native one into the log of the run it ended.
 */
object ExitReasons {
    const val CHANNEL = "rift/exit_reasons"

    private const val MAX = 5
    private const val DAYS = 14L

    fun register(context: Context, messenger: BinaryMessenger): MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "recent" -> result.success(recent(context))
                    else -> result.notImplemented()
                }
            }
        }

    private fun recent(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        val since = System.currentTimeMillis() - DAYS * 24 * 60 * 60 * 1000
        return manager.getHistoricalProcessExitReasons(context.packageName, 0, MAX)
            .filter { it.timestamp >= since }
            .map {
                mapOf(
                    "timestamp" to it.timestamp,
                    "pid" to it.pid,
                    "process" to it.processName,
                    "reason" to it.reason,
                    "status" to it.status,
                    "importance" to it.importance,
                    "pssKb" to it.pss,
                    "rssKb" to it.rss,
                    "description" to it.description,
                )
            }
    }
}
