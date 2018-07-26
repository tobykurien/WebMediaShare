package com.tobykurien.webmediashare.activity

import org.xtendroid.utils.BasePreferences
import com.tobykurien.webmediashare.R
import com.tobykurien.webmediashare.R.xml
import android.os.Bundle
import android.preference.PreferenceActivity
import android.support.v7.app.AppCompatActivity

class Preferences extends AppCompatActivity {
	override protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState)
		setContentView(R.layout.preferences)
	}

	override protected void onPause() {
		super.onPause() // tell Webview to reload with new settings
		BasePreferences.clearCache()
		BaseWebAppActivity.reload = true
	}

}
