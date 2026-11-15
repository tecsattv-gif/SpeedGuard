package com.tecsattv.speedguard

import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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

    private var bootChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "speedguard/boot")
        bootChannel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // true só uma vez: quando foi aberto ao ligar o aparelho.
                    "consumeBoot" -> {
                        val boot = intent?.getBooleanExtra(EXTRA_BOOT, false) ?: false
                        intent?.removeExtra(EXTRA_BOOT)
                        result.success(boot)
                    }
                    // 1.42.1: segundos desde que o aparelho ligou.
                    "sinceBoot" -> result.success(SystemClock.elapsedRealtime() / 1000)
                    // 1.42.3: versão do Android (API).
                    "sdk" -> result.success(Build.VERSION.SDK_INT)
                    // 1.42.3: bipe do próprio Android (reserva do tocador).
                    "tone" -> {
                        try {
                            val tg = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
                            tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 300)
                            Handler(Looper.getMainLooper()).postDelayed({
                                try {
                                    tg.release()
                                } catch (e: Throwable) {
                                }
                            }, 700)
                            result.success(true)
                        } catch (e: Throwable) {
                            result.success(false)
                        }
                    }
                    // Minimiza o app (como apertar o botão Início).
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    // 1.42.1: o aviso de "aparelho ligou" chegou com o app já aberto (alguns
    // aparelhos, como o Garmin, reabrem o app sozinhos antes): avisa o Dart.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        try {
            if (intent.getBooleanExtra(EXTRA_BOOT, false)) {
                intent.removeExtra(EXTRA_BOOT)
                bootChannel?.invokeMethod("boot", null)
            }
        } catch (e: Throwable) {
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
