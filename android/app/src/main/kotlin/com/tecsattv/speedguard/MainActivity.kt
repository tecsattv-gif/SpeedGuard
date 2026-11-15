package com.tecsattv.speedguard

import android.content.Intent
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 1.39.0: ao fechar o SpeedGuard (tirar dos recentes / tela destruída), a
 * janela flutuante é fechada pelo próprio Android, sem depender do Dart.
 * Antes ela podia ficar por cima dos outros apps e a tela parava de
 * responder ao toque.
 *
 * 1.42.0: canal "speedguard/boot" — o Dart pergunta se o app foi aberto
 * pelo BootReceiver (ao ligar o aparelho) e pede para minimizar.
 */
class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_BOOT = "boot_minimized"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "speedguard/boot")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // true só uma vez: quando foi aberto ao ligar o aparelho.
                    "consumeBoot" -> {
                        val boot = intent?.getBooleanExtra(EXTRA_BOOT, false) ?: false
                        intent?.removeExtra(EXTRA_BOOT)
                        result.success(boot)
                    }
                    // Minimiza o app (como apertar o botão Início).
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        try {
            stopService(Intent(applicationContext, OverlayService::class.java))
        } catch (e: Throwable) {
        }
        super.onDestroy()
    }
}
