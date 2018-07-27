package com.tobykurien.webmediashare.db

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.webkit.CookieSyncManager
import com.tobykurien.webmediashare.data.Webapp
import java.util.List
import org.xtendroid.db.BaseDbService
import android.util.Log
import android.webkit.CookieManager
import com.tobykurien.webmediashare.utils.Debug

/**
 * Class to manage database queries. Uses Xtendroid's BaseDbService
 */
class DbService extends BaseDbService {
	public static val TABLE_WEBAPPS = "webapps"
	public static val TABLE_DOMAINS = "domain_names"

	protected new(Context context) {
		super(context, "webmediashare", 1)
	}

	def static getInstance(Context context) {
		return new DbService(context)
	}

	override onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
		super.onUpgrade(db, oldVersion, newVersion)
	}

	def List<Webapp> getWebapps() {
		findAll(TABLE_WEBAPPS, "lower(name) asc", Webapp)
	}

	def void saveCookies(Webapp webapp) {
		if (Debug.COOKIE) Log.d("cookie", "Saving cookies for " + webapp.url)
		var cookiesStr = CookieManager.instance.getCookie(webapp.url)
		if (cookiesStr != null) {
			update("webapps", #{
				"cookies" -> cookiesStr
			}, webapp.id)
		}
	}
}