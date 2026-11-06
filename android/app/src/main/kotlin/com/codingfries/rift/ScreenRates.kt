package com.codingfries.rift

import android.content.Context
import android.hardware.display.DisplayManager
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The fastest the phone's screen can run, which decides whether a share offers
 * 120 fps (`PhoneScreen`).
 *
 * Asked of the screen's modes rather than its current rate: a phone on an
 * adaptive setting may be at 60 at that moment and go to 120 once something
 * moves.
 */
object ScreenRates {
    const val CHANNEL = "rift/screen_rates"

    fun register(context: Context, messenger: BinaryMessenger): MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "top" -> result.success(top(context))
                    else -> result.notImplemented()
                }
            }
        }

    private fun top(context: Context): Double? =
        context.getSystemService(DisplayManager::class.java)
            ?.getDisplay(Display.DEFAULT_DISPLAY)
            ?.supportedModes
            ?.maxOfOrNull { it.refreshRate.toDouble() }
}
