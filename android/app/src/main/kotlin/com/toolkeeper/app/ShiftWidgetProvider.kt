package com.toolkeeper.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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
        views.setTextViewText(R.id.widget_site, siteName)
        views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
        if (startMillis > 0) {
          val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startMillis)
          views.setChronometer(R.id.widget_chronometer, base, null, true)
        }
        views.setTextViewText(R.id.widget_button, "Завершить смену")
        val endIntent = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse("toolkeeperwidget://end"))
        views.setOnClickPendingIntent(R.id.widget_button, endIntent)
      } else {
        views.setTextViewText(R.id.widget_status, "Смена не активна")
        views.setTextViewText(R.id.widget_site, "")
        views.setViewVisibility(R.id.widget_chronometer, View.GONE)
        views.setTextViewText(R.id.widget_button, "Начать смену")
        val startIntent = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse("toolkeeperwidget://start"))
        views.setOnClickPendingIntent(R.id.widget_button, startIntent)
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
