package com.tecsattv.speedguard

import android.content.Intent
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.android.FlutterActivity

/**
 * 1.39.0: ao fechar o SpeedGuard (tirar dos recentes / tela destruída), a
 * janela flutuante é fechada pelo próprio Android, sem depender do Dart.
 * Antes ela podia ficar por cima dos outros apps e a tela parava de
 * responder ao toque.
 */
class MainActivity : FlutterActivity() {
    override fun onDestroy() {
        try {
            stopService(Intent(applicationContext, OverlayService::class.java))
        } catch (e: Throwable) {
        }
        super.onDestroy()
    }
}
