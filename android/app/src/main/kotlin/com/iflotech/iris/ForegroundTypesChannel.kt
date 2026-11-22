package com.iflotech.iris

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `iris/foreground`: setServiceTypes [names] stores the foreground service's types where flutter_foreground_task
 * reads them when it (re)starts the service. The plugin fixes the types at start and has no call to change them; a
 * voice call joining push (or leaving it) needs the microphone type added (or dropped) without stopping the service,
 * so Dart stores them here and then calls the plugin's restartService.
 *
 * Tied to flutter_foreground_task 10.0.0's preference names (pinned in pubspec.yaml); check them on any upgrade.
 */
class ForegroundTypesChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "iris/foreground")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setServiceTypes" -> {
                val names = call.arguments as? List<*> ?: emptyList<Any>()
                var value = 0
                for (name in names) value = value or flag(name)
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                with(prefs.edit()) {
                    // No known type: leave the key out and the manifest's types apply, as the plugin does.
                    if (value > 0) putInt(KEY, value) else remove(KEY)
                    commit()
                }
                result.success(value)
            }
            else -> result.notImplemented()
        }
    }

    /** The same SDK gates as the plugin's own mapping. */
    private fun flag(name: Any?): Int = when (name) {
        "microphone" ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
        "remoteMessaging" ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            } else {
                0
            }
        else -> 0
    }

    fun dispose() = channel.setMethodCallHandler(null)

    private companion object {
        const val PREFS = "com.pravera.flutter_foreground_task.prefs.FOREGROUND_SERVICE_TYPES"
        const val KEY = "serviceTypes"
    }
}
