package com.toolkeeper.tooltrack_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ShiftWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
          context: Context,
          appWidgetManager: AppWidgetManager,
          appWidgetIds: IntArray,
          widgetData: SharedPreferences,
        ) {
      appWidgetIds.forEach { widgetId ->
          val active = widgetData.getBoolean("shiftActive", false)
            val siteName = widgetData.getString("shiftSiteName", "") ?: ""
          val startMillis = widgetData.getLong("shiftStartMillis", 0L)

            val views = RemoteViews(context.packageName, R.layout.shift_widget_layout)

            if (active) {
                views.setTextViewText(R.id.widget_status, "Смена активна")
                  views.setTextColor(R.id.widget_dot, 0xFF4CAF50.toInt())
                    views.setTextViewText(R.id.widget_site, siteName)
                      views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
                      if (startMillis > 0) {
                          val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startMillis)
                            views.setChronometer(R.id.widget_chronometer, base, null, true)
                      }
                      views.setTextViewText(R.id.widget_button, "Завершить смену")
                      views.setInt(R.id.widget_button, "setBackgroundResource", R.drawable.widget_button_end)
                      views.setOnClickPendingIntent(R.id.widget_button, buildPendingIntent(context, "end", widgetId))
            } else {
              views.setTextViewText(R.id.widget_status, "Смена не активна")
              views.setTextColor(R.id.widget_dot, 0xFF9E9E9E.toInt())
              views.setTextViewText(R.id.widget_site, "")
              views.setViewVisibility(R.id.widget_chronometer, View.GONE)
              views.setTextViewText(R.id.widget_button, "Начать смену")
              views.setInt(R.id.widget_button, "setBackgroundResource", R.drawable.widget_button_start)
              views.setOnClickPendingIntent(R.id.widget_button, buildPendingIntent(context, "start", widgetId))
            }

            appWidgetManager.updateAppWidget(widgetId, views)
      }
    }

    private fun buildPendingIntent(context: Context, action: String, widgetId: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
              this.action = Intent.ACTION_VIEW
              data = Uri.parse("toolkeeperwidget://$action")
              flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val requestCode = if (action == "start") widgetId * 10 + 1 else widgetId * 10 + 2
      return PendingIntent.getActivity(
          context, requestCode, intent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
