package com.hari.otpbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

/** Notifies that a file arrived from the Mac (saved to Downloads). Tapping it
 *  opens the file in a suitable app. */
object FileNotify {
    private const val CHANNEL_ID = "otp_file"

    fun show(context: Context, name: String, uri: Uri?, mime: String) {
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mgr.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "File from Mac", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setContentTitle("File received from Mac")
            .setContentText("$name — tap to open")
            .setSmallIcon(NotifIcons.small)
            .setLargeIcon(NotifIcons.large(context))
            .setAutoCancel(true)

        if (uri != null) {
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val pi = PendingIntent.getActivity(
                context, name.hashCode(), view,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setContentIntent(pi)
        }

        mgr.notify(name.hashCode(), builder.build())
    }
}
