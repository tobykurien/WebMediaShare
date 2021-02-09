package com.tobykurien.webmediashare.activity;

import android.annotation.TargetApi
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.graphics.drawable.ColorDrawable
import android.support.v4.content.LocalBroadcastManager
import android.support.v4.content.pm.ShortcutManagerCompat
import android.support.v7.app.AlertDialog
import android.util.Log
import android.view.ContextMenu
import android.view.ContextMenu.ContextMenuInfo
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.webkit.CookieManager
import android.webkit.WebView
import android.widget.ImageView
import android.os.Message
import android.os.Handler
import com.tobykurien.webmediashare.R
import com.tobykurien.webmediashare.adapter.WebappsAdapter
import com.tobykurien.webmediashare.data.MediaUrl
import com.tobykurien.webmediashare.data.ThirdPartyDomain
import com.tobykurien.webmediashare.db.DbService
import com.tobykurien.webmediashare.fragment.DlgCertificate
import com.tobykurien.webmediashare.fragment.DlgSaveWebapp
import com.tobykurien.webmediashare.utils.FaviconHandler
import com.tobykurien.webmediashare.utils.Settings
import com.tobykurien.webmediashare.webviewclient.WebClient
import com.tobykurien.webmediashare.webviewclient.WebViewUtils
import java.util.ArrayList
import java.util.List
import java.util.Set
import android.app.ActivityManager.TaskDescription;

import static extension org.xtendroid.utils.AsyncBuilder.*
import static extension com.tobykurien.webmediashare.utils.Dependencies.*
import static extension org.xtendroid.utils.AlertUtils.*
import static extension org.xtendroid.utils.TimeUtils.*

import com.tobykurien.webmediashare.fragment.DlgShareMedia
import java.io.File
import java.util.Date
import java.net.URL
import java.net.HttpURLConnection
import com.google.common.io.ByteStreams
import java.io.FileOutputStream
import android.view.WindowManager

/**
 * Extensions to the main activity for Android 3.0+, or at least it used to be.
 * Now the core functionality is in the base class and the UI-related stuff is
 * here.
 * 
 * @author toby
 */
@TargetApi(Build.VERSION_CODES.HONEYCOMB)
public class WebAppActivity extends BaseWebAppActivity {
	val static DEFAULT_FONT_SIZE = 2 // "normal" font size value from arrays.xml
	// variables to track dragging for actionbar auto-hide
	var protected float startX;
	var protected float startY;

	var private MenuItem stopMenu = null;
	var private MenuItem imageMenu = null;
	var private MenuItem castMenu = null;
	var private MenuItem shortcutMenu = null;
	var private Bitmap unsavedFavicon = null;
	val iconHandler = new FaviconHandler(this)

	val mediaUrlReceiver = new BroadcastReceiver() {
		override onReceive(Context context, Intent intent) {
			setCastMenuVisibility()
		}
	}

	override onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);

		// keep screen on
		window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

		// setup actionbar
		val ab = getSupportActionBar();
		ab.setDisplayShowTitleEnabled(false);
		ab.setDisplayShowCustomEnabled(true);
		ab.setDisplayHomeAsUpEnabled(true);
		ab.setCustomView(R.layout.actionbar_favicon);

		registerForContextMenu(wv)

		// register to listen for media URL broadcasts
		LocalBroadcastManager.getInstance(this).registerReceiver(mediaUrlReceiver,
			new IntentFilter(WebClient.MEDIA_URL_FOUND))

		wv.onLongClickListener = [
			var url = wv.hitTestResult.extra

			if (wv.hitTestResult.type == WebView.HitTestResult.UNKNOWN_TYPE ||
				wv.hitTestResult.type == WebView.HitTestResult.SRC_ANCHOR_TYPE ||
				wv.hitTestResult.type == WebView.HitTestResult.IMAGE_TYPE ||
				wv.hitTestResult.type == WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE) {
				val Message message = new Message();
			    message.setTarget(new Handler()[msg|
			        var String title = msg.getData().getString("title");
					if (title === null) title = msg.getData().getString("alt");
					if (title === null) title = webapp.name;

			        var String href = msg.getData().getString("url");
					if (href === null) href = msg.getData().getString("href");
					if (href === null) href = msg.getData().getString("src");

					if (href !== null) {
						shareURL(href, title);
						return true;
					}
				]);
    			wv.requestFocusNodeHref(message);
			} else if (url !== null) {
				shareURL(url, webapp.name);
				return true;
			}
			
			return false
		]

		// load a favico if it already exists
		val favIcon = iconHandler.getFavIcon(webapp.id)
		updateActionBar(favIcon)

		downloadAdblockList()
	}

	override protected onResume() {
		super.onResume()

		MainActivity.handleFullscreenOptions(this)

		if (settings.shouldHideActionBar(fromShortcut)) {
			supportActionBar.hide();
			wv.setOnTouchListener = null
		} else {
			autohideActionbar();
		}

        setCastMenuVisibility()
	}

	override protected onPause() {
		super.onPause()

		if (webappId < 0) {
			// clean up data left behind by this webapp
			clearWebviewCache(wv)
		}
	}

	override onStop() {
		LocalBroadcastManager.getInstance(this).unregisterReceiver(mediaUrlReceiver)
		super.onStop()
	}


	override onCreateContextMenu(ContextMenu menu, View v, ContextMenuInfo menuInfo) {
		super.onCreateContextMenu(menu, v, menuInfo)

		// signifies a long-press on whitespace or text
		if (settings.shouldHideActionBar(fromShortcut)) {
			var ab = supportActionBar
			if (ab.isShowing) ab.hide else ab.show
		}
	}

	override onCreateOptionsMenu(Menu menu) {
		// super.onCreateOptionsMenu(menu);
		var inflater = getMenuInflater();
		inflater.inflate(R.menu.webapps_menu, menu);

		stopMenu = menu.findItem(R.id.menu_stop);
		imageMenu = menu.findItem(R.id.menu_image);
		imageMenu.setChecked(Settings.getSettings(this).isLoadImages());
		updateImageMenu();
		castMenu = menu.findItem(R.id.menu_cast);
        setCastMenuVisibility()

		shortcutMenu = menu.findItem(R.id.menu_shortcut);
		if (webappId < 0) {
			shortcutMenu.enabled = false;
		}

		return true;
	}

	override onOptionsItemSelected(MenuItem item) {
		switch (item.getItemId()) {
			case android.R.id.home: {
				finish();
				return true;
			}
			case R.id.menu_3rd_party: {
				dlg3rdParty();
				return true;
			}
			case R.id.menu_save: {
				dlgSave();
				return true;
			}
			case R.id.menu_stop: {
				if (stopMenu != null && !stopMenu.isChecked()) {
					wv.reload()
				} else {
					wv.stopLoading();
				}
				return true;
			}
			case R.id.menu_image: {
				if (imageMenu != null) {
					imageMenu.setChecked(!imageMenu.isChecked());
					if (imageMenu.isChecked()) {
						toast(getString(R.string.toast_images_enabled))
					} else {
						toast(getString(R.string.toast_images_disabled))
					}
					updateImageMenu();
					setupWebView();
				}
				return true;
			}
			case R.id.menu_cast: {
				castMedia()
				return true
			}
			case R.id.menu_font_size: {
				showFontSizeDialog()
				return true;
			}
			case R.id.menu_user_agent: {
				showUserAgentDialog()
				return true;
			}
			case R.id.menu_certificate: {
				showCertificateDetails()
				return true;
			}
			case R.id.menu_share: {
				shareURL(wv.url, webapp.name)
				return true;
			}
			case R.id.menu_shortcut: {
				addShortcut();
				return true;
			}
			case R.id.menu_settings: {
				var i = new Intent(this, Preferences);
				startActivity(i);
				return true;
			}
			case R.id.menu_exit: {
				Runtime.getRuntime().exit(0); // hard exit
				return true;
			}
		}

		return super.onOptionsItemSelected(item);
	}

	def showFontSizeDialog() {
		val int fontSize = if(webapp.fontSize >= 0) webapp.fontSize else DEFAULT_FONT_SIZE
		new AlertDialog.Builder(this)
			.setTitle(R.string.menu_text_size)
			.setSingleChoiceItems(R.array.text_sizes, fontSize, [ dlg, value |
				WebViewUtils.instance.setTextSize(wv, value)
				webapp.fontSize = value
			])
			.setPositiveButton(android.R.string.ok, [ dlg, i |
				// save font size
				if (webappId > 0) {
					db.update(DbService.TABLE_WEBAPPS, #{
						'fontSize' -> webapp.fontSize
					}, webappId)
				}
	
				dlg.dismiss
			])
			.create()
			.show()
	}

	def showUserAgentDialog() {
		val String userAgent = if(webapp.userAgent != null) webapp.userAgent else settings.userAgent
		val iUserAgent = resources.getStringArray(R.array.user_agent_strings).indexOf(userAgent)
		new AlertDialog.Builder(this)
			.setTitle(R.string.menu_user_agent)
			.setSingleChoiceItems(R.array.user_agents, iUserAgent, [ dlg, value |
				webapp.userAgent = resources.getStringArray(R.array.user_agent_strings).get(value)
				wv.settings.userAgentString = webapp.userAgent
			])
			.setPositiveButton(android.R.string.ok, [ dlg, i |
				// save user agent
				if (webappId > 0) {
					db.update(DbService.TABLE_WEBAPPS, #{
						'userAgent' -> webapp.userAgent
					}, webappId)
					wv.reload()
				}
	
				dlg.dismiss
			])
			.create()
			.show()
	}

	def void updateImageMenu() {
		Settings.getSettings(this).setLoadImages(imageMenu.isChecked());
		imageMenu.setIcon(
			if (imageMenu.isChecked())
				R.drawable.ic_action_image
			else
				R.drawable.ic_action_broken_image
		);
	}

	override onPageLoadStarted() {
		super.onPageLoadStarted();

        setCastMenuVisibility()

		if (stopMenu != null) {
			stopMenu.setTitle(R.string.menu_stop);
			stopMenu.setIcon(R.drawable.ic_action_stop);
			stopMenu.setChecked(true);
		}
	}

	override onPageLoadDone() {
		super.onPageLoadDone();

		val domain = WebClient.getRootDomain(webapp.url)
		val cookies = CookieManager.instance.getCookie(webapp.url)
		if (webapp != null && cookies != null && webapp.id > 0 &&
				!cookies.equals(webapp.cookies)) {
			db.saveCookies(webapp)
		}

		if (stopMenu != null) {
			stopMenu.setTitle(R.string.menu_refresh);
			stopMenu.setIcon(R.drawable.ic_action_refresh);
			stopMenu.setChecked(false);
		}

		// webview sometime misbehaves, so forcefully check for new urls
		mediaUrlReceiver.onReceive(this, null)

		// and sometimes it takes a while for URLs to register
		for (var i=0; i < 20; i++) async [
			Thread.sleep(500)
			return true
		].then[
			mediaUrlReceiver.onReceive(this, null)
		]
	}

	override onReceivedFavicon(WebView view, Bitmap icon) {
		super.onReceivedFavicon(view, icon)
		var iconImg = supportActionBar.customView.findViewById(R.id.favicon) as ImageView;
		iconImg.setImageBitmap(icon);

		// also save favicon
		if (webappId >= 0) {
			async [ builder, params |
				new FaviconHandler(this).saveFavIcon(webappId, icon)
				return true
			].onError [ ex |
				Log.e("favicon", "error saving icon", ex)
			].start()
		} else {
			unsavedFavicon = icon
		}
	}

	override onFullscreenChanged(boolean isFullscreen) {
		super.onFullscreenChanged(isFullscreen)

		if (isFullscreen && supportActionBar.isShowing) {
			// always hide the action bar in fullscreen (video) mode
			supportActionBar.hide()
		}
		if (!isFullscreen && !settings.isHideActionbar && !settings.isFullHideActionbar) {
			// un-hide the action bar when coming out of fullscreen
			supportActionBar.show()
		}
	}

	/**
	 * Show a dialog to the user to allow saving a webapp
	 */
	def private void dlgSave() {
		var dlg = new DlgSaveWebapp(
						webappId, wv.getTitle(), wv.getUrl(), 
						wv.certificate,
						unblock);

		val isNewWebapp = if(webappId < 0) true else false;

		dlg.setOnSaveListener [ wapp |
			putWebappId(wapp.id)
			webapp = wapp

			// save any unblocked domains and cookies
			if (isNewWebapp) {
				saveWebappUnblockList(webappId, unblock)
				db.saveCookies(webapp)
			}

			// if we have unsaved icon, save it
			if (unsavedFavicon != null) {
				onReceivedFavicon(wv, unsavedFavicon)
				unsavedFavicon = null
			}

			shortcutMenu.enabled = true;
			shortcutMenu.visible = true;

			return null
		]

		dlg.show(getSupportFragmentManager(), "save");
	}

	/**
	 * Show a dialog to allow user to unblock or re-block third party domains
	 */
	def private void dlg3rdParty() {
		async [ builder, params |
			// get the saved list of whitelisted domains
			db.findByFields(DbService.TABLE_DOMAINS, #{
				"webappId" -> webappId
			}, null, ThirdPartyDomain)
		].then [ List<ThirdPartyDomain> whitelisted |
			// add all whitelisted domains
			val domains = new ArrayList(whitelisted.map[domain])
			val whitelist = new ArrayList(domains.map[true])

			// add all blocked domains
			for (blockedDomain : wc.getBlockedHosts()) {
				val d = WebClient.getRootDomain(blockedDomain)
				if(d !== null && !domains.contains(d)) {
					domains.add(d)
					whitelist.add(false)
				}
			}

			// show blocked 3rd party domains and allow user to allow them
			new AlertDialog.Builder(this)
				.setTitle(R.string.blocked_root_domains)
				.setMultiChoiceItems(domains, whitelist, [ d, pos, checked |
					if (checked) {
						unblock.add(domains.get(pos).intern());
					} else {
						unblock.remove(domains.get(pos).intern());
					}
					Log.d("unblock", unblock.toString)
				])
				.setPositiveButton(R.string.unblock, [ d, pos |
					saveWebappUnblockList(webappId, unblock)
					wc.unblockDomains(unblock);
					clearWebviewCache(wv)
					wv.reload();
					d.dismiss();
				])
				.create()
				.show();
		].onError [ Exception e |
			toast(e.class.name + " " + e.message)
		].start()
	}

	def castMedia() {
		var MediaUrl mu = null

		// if we have any media URL's, show dem
		if (wc.mediaUrls == null || wc.mediaUrls.length == 0) {
            setCastMenuVisibility()
		} else {
			new DlgShareMedia(wc.mediaUrls)
				.show(supportFragmentManager, "cast")
		}
	}
	
	def showCertificateDetails() {
		var dlg = new DlgCertificate(wv.certificate)
		dlg.show(supportFragmentManager, "certificate")
	}

	def clearWebviewCache(WebView wv) {
		// this is disabled as it will clear all existing cache when opening a new webapp
//		wv.clearCache(true);
//		deleteDatabase("webview.db");
//		deleteDatabase("webviewCache.db");
	}

	def void saveWebappUnblockList(long webappId, Set<String> unblock) {
		if (webappId >= 0) {
			async [ builder, params |
				// save the unblock list
				// clear current list
				db.execute(R.string.dbDeleteDomains, #{"webappId" -> webappId});

				if (unblock != null && unblock.size() > 0) {
					// add new items
					for (domain : unblock) {
						if (!WebClient.getHost(webapp.url).equals(domain)) {
							db.insert(DbService.TABLE_DOMAINS, #{
								"webappId" -> webappId,
								"domain" -> domain
							});
						}
					}
				}

				return null
			].start()
		}
	}

	/**
	 * Attempt to make the actionBar auto-hide and auto-reveal based on drag
	 * 
	 * @param activity
	 * @param wv
	 */
	def void autohideActionbar() {
		wv.setOnTouchListener [ view, event |
			if (settings.isHideActionbar()) {
				if (event.getAction() == MotionEvent.ACTION_DOWN) {
					startY = event.getY();
				}

				if (event.getAction() == MotionEvent.ACTION_MOVE) {
					// avoid juddering by waiting for large-ish drag
					if (Math.abs(startY - event.getY()) > new ViewConfiguration().getScaledTouchSlop() * 5) {
						if (startY < event.getY()) {
							supportActionBar.show();
						} else {
							supportActionBar.hide();
						}
					}
				}
			}

			return false;
		]
	}

	def addShortcut() {
		val shortcut = ShortcutActivity.getShortcut(this, webapp)
		ShortcutManagerCompat.requestPinShortcut(this, shortcut.build(), null)
		toast(getString(R.string.msg_shortcut_added))
	}

    def setCastMenuVisibility() {
        if (castMenu != null) {
			var state = castMenu.visible
            if (wc?.mediaUrls != null) {
                castMenu.visible = wc.mediaUrls.length > 0
            } else {
                castMenu.visible = false
            }

			if (state != castMenu.visible) {
				// refresh the icons
				getSupportActionBar.invalidateOptionsMenu()
			}
        }
    }

	def downloadAdblockList() {
		// download adbock list
		val url = "https://pgl.yoyo.org/as/serverlist.php?showintro=0;hostformat=plain"
		val adhosts = getCacheDir().absolutePath + "/adhosts"
		val f = new File(adhosts)
		if (!f.exists() || !f.canRead() || f.lastModified < 1.day.ago.time) {
			Log.d("adblock", "Updating adblock list")
			async [ builder, params |
				var con = new URL(url).openConnection() as HttpURLConnection
				con.connect()
				ByteStreams.copy(con.inputStream, new FileOutputStream(f))
				con.inputStream.close()
				return true
			].onError [ error |
				Log.e("adblock", "Error updating adhosts", error)
			].start()
		}
	}

	def updateActionBar(File favIcon) {
		val iconImg = supportActionBar.customView.findViewById(R.id.favicon) as ImageView;
		iconImg.imageResource = R.drawable.ic_action_site
		WebappsAdapter.loadFavicon(this, favIcon, iconImg)
		val colour = FaviconHandler.getDominantColor(favIcon)
		supportActionBar.backgroundDrawable = new ColorDrawable(colour)
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
		    val window = getWindow();
		    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
		    window.setStatusBarColor(colour);
		}	

		val taskDesc = new TaskDescription(webapp.name, BitmapFactory.decodeFile(favIcon.absolutePath), colour);
		setTaskDescription(taskDesc);
	}	

	def shareURL(String shareUrl, String shareTitle) {
		var share = new Intent(Intent.ACTION_SEND)
		share.setType("text/plain")		
		share.addFlags(Intent.FLAG_ACTIVITY_CLEAR_WHEN_TASK_RESET)
		share.putExtra(Intent.EXTRA_SUBJECT, shareTitle);
		share.putExtra(Intent.EXTRA_TEXT, shareUrl);
		startActivity(Intent.createChooser(share, getString(R.string.menu_share)));
	}
}
