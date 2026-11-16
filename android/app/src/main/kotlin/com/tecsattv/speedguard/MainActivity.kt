package com.tecsattv.speedguard

import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
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
                    // 1.42.4: fabricante/marca/modelo (para reconhecer o Garmin).
                    "maker" -> result.success(
                        "${Build.MANUFACTURER} ${Build.BRAND} ${Build.MODEL}")
                    // 1.42.6 (Garmin): toca o bipe do app (o mesmo som do
                    // Android 7+) direto pelo Android, mais alto.
                    "beep" -> {
                        val wav = call.argument<ByteArray>("wav")
                        val vol = call.argument<Double>("volume") ?: 1.0
                        result.success(wav != null && playWav(wav, vol))
                    }
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

    /**
     * 1.42.6 (Garmin): toca um bipe do app (WAV de 16 bits) direto pelo
     * AudioTrack, sem o tocador do Flutter. O som é levado ao volume máximo
     * e reforçado (limite suave, sem estalo), porque no alto-falante do
     * Garmin o bipe saía baixo. Devolve false se não deu para tocar.
     */
    private var beepTrack: AudioTrack? = null

    private fun playWav(wav: ByteArray, volume: Double): Boolean {
        try {
            fun u16(i: Int): Int =
                (wav[i].toInt() and 0xff) or ((wav[i + 1].toInt() and 0xff) shl 8)
            fun u32(i: Int): Int = u16(i) or (u16(i + 2) shl 16)

            var rate = 22050
            var channels = 1
            var bits = 16
            var dataOff = -1
            var dataLen = 0
            var pos = 12
            while (pos + 8 <= wav.size) {
                val id = String(wav, pos, 4, Charsets.US_ASCII)
                val len = u32(pos + 4)
                if (id == "fmt " && pos + 24 <= wav.size) {
                    channels = u16(pos + 10)
                    rate = u32(pos + 12)
                    bits = u16(pos + 22)
                } else if (id == "data") {
                    dataOff = pos + 8
                    dataLen = minOf(len, wav.size - dataOff)
                    break
                }
                if (len < 0) break
                pos += 8 + len + (len and 1)
            }
            if (dataOff < 0 || bits != 16 || dataLen < 4) return false

            val n = dataLen / 2
            val pcm = ShortArray(n)
            var peak = 1
            for (i in 0 until n) {
                val v = u16(dataOff + 2 * i).toShort()
                pcm[i] = v
                val a = Math.abs(v.toInt())
                if (a > peak) peak = a
            }
            // Volume máximo, sem distorcer (1.42.8: o reforço de 1,8x da
            // 1.42.6 deixava o som áspero; os bipes do Garmin já vêm cheios).
            val vol = Math.max(0.1, Math.min(1.0, volume))
            for (i in 0 until n) {
                val x = pcm[i].toDouble() / peak
                pcm[i] = (x * 32767.0 * vol).toInt().toShort()
            }

            try {
                beepTrack?.release()
            } catch (e: Throwable) {
            }
            beepTrack = null

            val track = AudioTrack(
                AudioManager.STREAM_MUSIC,
                rate,
                if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO
                else AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                n * 2,
                AudioTrack.MODE_STATIC
            )
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                track.release()
                return false
            }
            if (track.write(pcm, 0, n) <= 0) {
                track.release()
                return false
            }
            track.play()
            beepTrack = track
            val ms = n.toLong() * 1000L / (rate.toLong() * channels) + 400L
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    if (beepTrack === track) beepTrack = null
                    track.release()
                } catch (e: Throwable) {
                }
            }, ms)
            return true
        } catch (e: Throwable) {
            return false
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
