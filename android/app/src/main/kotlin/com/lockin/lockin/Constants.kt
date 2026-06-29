package com.lockin.lockin

object Constants {
    const val CHANNEL_ID = "lockin_block_service_channel"
    const val NOTIF_ID = 888

    const val INSTAGRAM_PKG = "com.instagram.android"
    const val WHATSAPP_PKG = "com.whatsapp"
    const val SNAPCHAT_PKG = "com.snapchat.android"

    val DEFAULT_APPS = listOf(INSTAGRAM_PKG, WHATSAPP_PKG, SNAPCHAT_PKG)

    const val USAGE_WINDOW_MS = 4 * 60 * 60 * 1000L
    const val USAGE_LIMIT_MS = 40 * 60 * 1000L
    const val BLOCK_DURATION_MS = 30 * 60 * 1000L
}
