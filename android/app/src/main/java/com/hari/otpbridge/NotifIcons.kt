package com.hari.otpbridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory

/** Shared notification icons: white mascot silhouette for the status-bar small
 *  icon, and the full-color mascot for the large icon. */
object NotifIcons {
    val small = R.drawable.ic_stat_mascot

    fun large(context: Context): Bitmap? =
        runCatching { BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher) }.getOrNull()
}
