package com.lockin.lockin

object Constants {
    const val CHANNEL_ID = "lockin_block_service_channel"
    const val NOTIF_ID = 888

    const val INSTAGRAM_PKG = "com.instagram.android"
    const val WHATSAPP_PKG = "com.whatsapp"
    const val SNAPCHAT_PKG = "com.snapchat.android"

    val DEFAULT_APPS = listOf(INSTAGRAM_PKG, WHATSAPP_PKG, SNAPCHAT_PKG)

    const val DEFAULT_USAGE_WINDOW_MS = 4 * 60 * 60 * 1000L
    const val TEST_USAGE_WINDOW_MS = 60 * 1000L
    const val DEFAULT_USAGE_LIMIT_MS = 40 * 60 * 1000L
    const val MIN_USAGE_WINDOW_HOURS = 3
    const val MAX_USAGE_WINDOW_HOURS = 24
    const val MIN_USAGE_LIMIT_MINUTES = 5
    const val BLOCK_DURATION_MS = 30 * 60 * 1000L
}
