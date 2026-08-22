package com.codingfries.rift

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Picture-in-picture, so a video call survives leaving the app.
 *
 * Done here rather than through a package because the ones on pub.dev learn
 * the current mode by polling the platform channel — one round trip every ten
 * milliseconds, for the life of the process. Android already pushes the
 * transition through [onPictureInPictureModeChanged], so this listens instead
 * of asking.
 *
 * Dart decides *whether* the call is worth floating (there has to be a remote
 * camera or a shared screen to see) and says so through `setAutoEnter`. The
 * activity holds that as a mode rather than a command, because the moment the
 * window has to shrink is chosen by the user, not by us:
 *
 * - Android 12 and up: `setAutoEnterEnabled` hands the whole transition to the
 *   system, which is what makes the gesture animate smoothly instead of
 *   snapping after the app has already left.
 * - Below that there is no such flag, so [onUserLeaveHint] — the last callback
 *   before the app goes away — is where the window has to be shrunk by hand.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "rift/pip"

        /** A call is a video call; the window it shrinks to should be one too. */
        val ASPECT = Rational(16, 9)
    }

    private var channel: MethodChannel? = null

    /** Whether there is currently something worth floating. */
    private var autoEnter = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isPipSupported())
                    "setAutoEnter" -> {
                        autoEnter = call.argument<Boolean>("enabled") ?: false
                        applyParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    /**
     * PiP can be missing even on a new enough Android: manufacturers and device
     * admins can both take it away, which is what the system feature reports.
     */
    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(ASPECT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
        }
        return builder.build()
    }

    private fun applyParams() {
        if (!isPipSupported()) return
        setPictureInPictureParams(buildParams())
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12 and up shrink the window themselves; entering here as well
        // would be asking twice for the same thing.
        if (!autoEnter || !isPipSupported()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        enterPictureInPictureMode(buildParams())
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
