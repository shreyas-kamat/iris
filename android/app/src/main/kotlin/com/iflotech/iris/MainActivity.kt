package com.iflotech.iris

import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var pcmOut: PcmOutChannel? = null
    private var foregroundTypes: ForegroundTypesChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pcmOut = PcmOutChannel(flutterEngine.dartExecutor.binaryMessenger)
        foregroundTypes = ForegroundTypesChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pcmOut?.dispose()
        pcmOut = null
        foregroundTypes?.dispose()
        foregroundTypes = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // The app's engine (and any voice call in it) is going away. The service may outlive it for push; tell its
        // isolate, which takes the notification back or, with push off, stops the service.
        if (!isChangingConfigurations) ForegroundService.sendData(mapOf("app_gone" to true))
        super.onDestroy()
    }
}
