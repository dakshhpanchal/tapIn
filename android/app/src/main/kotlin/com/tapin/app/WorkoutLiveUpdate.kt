package com.tapin.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle

/**
 * The notification for the workout in progress.
 *
 * On Android 16 and later it asks to be promoted to a Live Update, so it shows
 * as a chip with the elapsed time in the status bar, and as an expanded card
 * with a progress bar (one segment per exercise, filling as sets are ticked)
 * on the lock screen and at the top of the shade. On older versions, or when
 * the user has turned Live Updates off for the app, the same notification is an
 * ordinary ongoing one with a timer and a plain progress bar.
 *
 * It is a plain notification, not a foreground service: nothing runs in the
 * background, the timer is the system's chronometer counting from the start
 * time, and the app removes the notification when the workout ends.
 */
object WorkoutLiveUpdate {
    private const val CHANNEL_ID = "workout_live"
    private const val NOTIFICATION_ID = 4201

    // Notification.EXTRA_REQUEST_PROMOTED_ONGOING, spelled out so this compiles
    // and runs the same on every Android version.
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    fun areNotificationsEnabled(context: Context): Boolean =
        manager(context).areNotificationsEnabled()

    /** Whether the system will promote it: Android 16+ and not switched off by the user. */
    fun canPromote(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 36 && manager(context).canPostPromotedNotifications()

    fun show(
        context: Context,
        title: String,
        text: String,
        startedAtMillis: Long,
        doneSets: Int,
        totalSets: Int,
        segments: List<Int>,
        channelName: String,
        channelDescription: String,
    ) {
        val nm = manager(context)
        if (!nm.areNotificationsEnabled()) return
        ensureChannel(nm, channelName, channelDescription)

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_workout)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            // The elapsed time, counted by the system from the start.
            .setWhen(startedAtMillis)
            .setShowWhen(true)
            .setUsesChronometer(true)

        if (totalSets > 0) builder.setSubText("$doneSets of $totalSets sets")

        // Ask to be a Live Update. Harmless where it is not supported.
        builder.addExtras(Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })

        if (totalSets > 0) {
            if (Build.VERSION.SDK_INT >= 36) {
                val parts = segments.filter { it > 0 }.ifEmpty { listOf(totalSets) }
                builder.setStyle(
                    Notification.ProgressStyle()
                        .setStyledByProgress(true)
                        .setProgressSegments(parts.map { Notification.ProgressStyle.Segment(it) })
                        .setProgress(doneSets.coerceIn(0, parts.sum())),
                )
            } else {
                builder.setProgress(totalSets, doneSets.coerceIn(0, totalSets), false)
            }
        }

        nm.notify(NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        manager(context).cancel(NOTIFICATION_ID)
    }

    private fun manager(context: Context): NotificationManager =
        context.getSystemService(NotificationManager::class.java)

    private fun ensureChannel(nm: NotificationManager, name: String, description: String) {
        // Quiet: it is a status display, so it must not make a sound or
        // vibrate. Not IMPORTANCE_MIN, because that makes it ineligible to be
        // promoted to a Live Update.
        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply {
            this.description = description
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(channel)
    }
}
