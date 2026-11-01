package com.ruview.wifi

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * نشاط أندرويد الرئيسي.
 *
 * اتصال WebSocket/UDP يتم من طبقة Dart (`dart:io`) مباشرة، ولا نحتاج أي
 * مكتبة طرف ثالث. القناتان الأصليتان هنا تخدم فقط ما لا تستطيعه Dart وحدها:
 *
 *  • `ruview/alerts`    — إشعارات نظام + طلب إذن أندرويد 13.
 *  • `ruview/emergency` — فتح لوحة الاتصال على رقم الطوارئ (`ACTION_DIAL`).
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALERTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }
                    "notify" -> {
                        val title = call.argument<String>("title") ?: DEFAULT_TITLE
                        val body = call.argument<String>("body") ?: ""
                        val critical = call.argument<Boolean>("critical") ?: false
                        showNotification(title, body, critical)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EMERGENCY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dial" -> {
                        val number = call.argument<String>("number").orEmpty()
                        if (number.isBlank()) {
                            result.success(false)
                        } else {
                            result.success(openDialer(number))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    private fun showNotification(title: String, body: String, critical: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // المستخدم لم يمنح الإذن بعد؛ التنبيه المرئي داخل التطبيق يكفيه.
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESCRIPTION
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(
                if (critical) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .build()

        manager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    /**
     * يفتح لوحة الاتصال مع الرقم جاهزًا — لا يتصل تلقائيًا (سلوك آمن متعمّد).
     * يعيد `false` إن لم يوجد تطبيق هاتف على الجهاز.
     */
    private fun openDialer(number: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (error: Exception) {
            false
        }
    }

    private companion object {
        const val ALERTS_CHANNEL = "ruview/alerts"
        const val EMERGENCY_CHANNEL = "ruview/emergency"
        const val CHANNEL_ID = "ruview_alerts"
        const val CHANNEL_NAME = "تنبيهات RuView"
        const val CHANNEL_DESCRIPTION = "تنبيهات السقوط والتسلل واضطراب التنفس"
        const val DEFAULT_TITLE = "RuView Wi-Fi"
        const val REQUEST_NOTIFICATIONS = 4021
    }
}
