package com.voiceagent.voice_agent

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The home-screen widget (ADR-PLATFORM-015): the owner's three numbers and the mic. It draws the
 * strings Dart saved (`HomeWidgetNumbers.toData()`, through `home_widget`) and decides one thing
 * itself: numbers of another day than today are not shown, as an app left overnight would show
 * yesterday's calories (V1's D10).
 */
class TodayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = render(context, widgetData, today())
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    companion object {
        private const val AMBER = 0xFFFFB300.toInt()
        private const val RED = 0xFFEF5350.toInt()
        private const val DIM = 0xB3FFFFFF.toInt()

        fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())

        fun render(context: Context, data: SharedPreferences, today: String): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            val day = data.getString("day", null)
            if (day == today) {
                views.setTextViewText(R.id.widget_kcal, data.getString("kcal", "—"))
                views.setTextViewText(R.id.widget_kcal_label, data.getString("kcal_label", ""))
                views.setTextColor(
                    R.id.widget_kcal,
                    when (data.getString("kcal_warning", "none")) {
                        "low" -> AMBER
                        "over" -> RED
                        else -> Color.WHITE
                    },
                )
                views.setTextViewText(R.id.widget_tasks_count, data.getString("tasks", "—"))
                views.setTextViewText(R.id.widget_tasks_label, data.getString("tasks_label", ""))
                views.setTextColor(
                    R.id.widget_tasks_label,
                    if (data.getBoolean("tasks_overdue", false)) AMBER else DIM,
                )
                views.setTextViewText(R.id.widget_matters, data.getString("matters", "—"))
                views.setTextViewText(R.id.widget_updated, data.getString("updated", ""))
            } else {
                // Nothing read yet, or the numbers are of another day.
                views.setTextViewText(R.id.widget_kcal, "—")
                views.setTextColor(R.id.widget_kcal, Color.WHITE)
                views.setTextViewText(
                    R.id.widget_kcal_label,
                    if (day == null) "otwórz aplikację" else "czekam na dzisiejszy dzień",
                )
                views.setTextViewText(R.id.widget_tasks_count, "—")
                views.setTextViewText(R.id.widget_tasks_label, "")
                views.setTextViewText(R.id.widget_matters, "—")
                views.setTextViewText(R.id.widget_updated, "")
            }
            views.setOnClickPendingIntent(R.id.widget_food, tap(context, "food", 1))
            views.setOnClickPendingIntent(R.id.widget_tasks, tap(context, "tasks", 2))
            views.setOnClickPendingIntent(R.id.widget_matters, tap(context, "matters", 3))
            views.setOnClickPendingIntent(R.id.widget_mic, tap(context, "listen", 4))
            return views
        }

        /** One PendingIntent per tap, told apart by its request code. */
        private fun tap(context: Context, what: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(WidgetTapBridge.ACTION)
                .putExtra(WidgetTapBridge.EXTRA_TAP, what)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            if (Build.VERSION.SDK_INT < 34) {
                return PendingIntent.getActivity(context, requestCode, intent, flags)
            }
            // The launcher sends it; the app, its creator, allows the start (as home_widget does).
            val options = ActivityOptions.makeBasic()
            if (Build.VERSION.SDK_INT >= 35) {
                options.setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                )
            } else {
                @Suppress("DEPRECATION")
                options.pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }
            return PendingIntent.getActivity(context, requestCode, intent, flags, options.toBundle())
        }
    }
}
