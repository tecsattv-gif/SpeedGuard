package com.tecsattv.speedguard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * 1.42.0: "Iniciar com o Android (minimizado)".
 * Quando o tablet/telefone termina de ligar, se a opção estiver ligada em
 * Configurações (preferência `boot_min`), abre o SpeedGuard; o app liga o
 * monitoramento e se minimiza sozinho (ver MainActivity e lib/boot_start.dart).
 *
 * O Android 10+ só deixa abrir a tela a partir do segundo plano se o app
 * tiver a permissão "Sobrepor a outros apps" — a mesma da bolha flutuante.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return
        try {
            // Preferências gravadas pelo Flutter (shared_preferences).
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            if (!prefs.getBoolean("flutter.boot_min", false)) return
            // Só o Android 10+ exige a permissão para abrir a tela daqui.
            if (Build.VERSION.SDK_INT >= 29 && !Settings.canDrawOverlays(context)) return
            val start = Intent(context, MainActivity::class.java)
            start.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            start.putExtra(MainActivity.EXTRA_BOOT, true)
            context.startActivity(start)
        } catch (e: Throwable) {
        }
    }
}
