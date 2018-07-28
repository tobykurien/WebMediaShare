package com.tobykurien.webmediashare.webviewclient

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.support.v7.app.AlertDialog
import android.util.Log
import android.view.View
import android.webkit.ClientCertRequest
import android.webkit.CookieManager
import android.webkit.CookieSyncManager
import android.webkit.SslErrorHandler
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import com.tobykurien.webmediashare.R
import com.tobykurien.webmediashare.activity.BaseWebAppActivity
import com.tobykurien.webmediashare.activity.WebAppActivity
import com.tobykurien.webmediashare.data.Webapp
import com.tobykurien.webmediashare.fragment.DlgCertificate
import com.tobykurien.webmediashare.utils.Debug
import java.lang.UnsupportedOperationException
import java.io.ByteArrayInputStream
import java.util.HashMap
import java.util.Set

import static extension com.tobykurien.webmediashare.utils.Dependencies.*
import static extension org.xtendroid.utils.AsyncBuilder.*

import com.tobykurien.webmediashare.db.DbService
import com.tobykurien.webmediashare.data.MediaUrl
import android.content.Context
import android.webkit.WebResourceRequest
import java.net.URLConnection
import java.net.URL
import java.util.List
import android.support.v4.media.MediaBrowserCompatUtils
import java.util.ArrayList
import android.support.v4.content.LocalBroadcastManager
import java.net.HttpURLConnection
import android.webkit.MimeTypeMap

class WebClient extends WebViewClient {
	public static val UNKNOWN_HOST = "999.999.999.999" // impossible hostname to avoid vuln
	public static val MEDIA_URL_FOUND = "com.tobykurien.webmediashare.MEDIA_URL_FOUND"

	package BaseWebAppActivity activity
	package Webapp webapp
	package WebView wv
	package View pd
	public  Set<String> domainUrls
	package var blockedHosts = new HashMap<String, Boolean>()
	public var ArrayList<MediaUrl> mediaUrls = newArrayList()

	new(BaseWebAppActivity activity, Webapp webapp, WebView wv, View pd, Set<String> domainUrls) {
		this.activity = activity
		this.webapp = webapp
		this.wv = wv
		this.pd = pd
		this.domainUrls = domainUrls
	}
	
	override onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
		super.onReceivedClientCertRequest(view, request)
		activity.onClientCertificateRequest(request)
	}

	override void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
		if (webapp == null || webapp.certIssuedBy == null) {
			// no SSL cert was saved for this webapp, so show SSL error to user
			var dlg = new DlgCertificate(error.certificate,
						activity.getString(R.string.title_cert_untrusted),
						activity.getString(R.string.cert_accept), [
							handler.proceed()
							true
						], [
							handler.cancel()
							true
						])
			dlg.show(activity.supportFragmentManager, "certificate")
		} else {
			// in onPageLoaded, WebAppActivity will check that the cert matches saved one
			handler.proceed()
		}
	}

	override void onPageFinished(WebView view, String url) {
		if(pd !== null) pd.setVisibility(View.GONE)
		activity.onPageLoadDone() 
		CookieSyncManager.getInstance().sync()
		super.onPageFinished(view, url)
	}

	override void onPageStarted(WebView view, String url, Bitmap favicon) {
		//Log.d("webclient", '''loading «url»''')
		if(pd !== null) pd.setVisibility(View.VISIBLE)
		activity.onPageLoadStarted()
		super.onPageStarted(view, url, favicon)
	}

	override boolean shouldOverrideUrlLoading(WebView view, String url) {

		if (!getRootDomain(url).equals(getRootDomain(webapp.url))) {
			try {
				handleExternalLink(view.context, Uri.parse(url), false)
			} catch (Exception e) {
				// probably bad url
				Log.e("WebClient", "error handling external url", e)
			}
			return true
		}

		return super.shouldOverrideUrlLoading(view, url)
	}

	def synchronized shareUrl(Uri uri, String contentType, Long contentLength) {
		for (mu : mediaUrls) {
			if (mu.toString().equals(uri.toString)) {
				// url already added
				return
			}
		}

		val mu = new MediaUrl()
		mu.uri = uri
		mu.contentType = contentType
		mu.contentLength = contentLength
		mediaUrls.add(mu)
		Log.d("WebClient", mediaUrls.toString)

		// alert other components that we found a media URL
		LocalBroadcastManager.getInstance(wv.context).sendBroadcast(new Intent
			(MEDIA_URL_FOUND))
	}

	def static handleExternalLink(Context activity, Uri uri, boolean openInExternalApp) {
		val domain = getRootDomain(uri.toString())
		Log.d("url_loading", domain)
		// first check if we have a saved webapp for this URI
		val webapps = activity.db.getWebapps().filter [wa|
			// check against root domains rather than sub-domains
			getRootDomain(wa.url).equals(getRootDomain(domain))
		]

		if (webapps == null || webapps.length == 0) {
            if (openInExternalApp) {
                Log.d("url_loading", "Sending to default app " + uri.toString)
                var Intent i = new Intent(Intent.ACTION_VIEW)
                i.setData(uri)
                activity.startActivity(i)
            } else {
				Log.d("url_loading", "Opening in new sandbox " + uri.toString)
                // open in new sandbox
                // delete all previous cookies
                CookieManager.instance.removeAllCookie()
                var i = new Intent(activity, WebAppActivity)
                i.action = Intent.ACTION_VIEW
                i.data = uri
                activity.startActivity(i)
            }
		} else {
			if (webapps.length > 1) {
				Log.d("url_loading", "More than one registered webapp for " + uri.toString)
				// TODO ask user to pick a webapp
				new AlertDialog.Builder(activity)
					.setTitle(R.string.title_open_with)
					.setItems(webapps.map[ name ], [a, pos|
						openWebapp(activity, webapps.get(pos), uri)
					])
					.setNegativeButton(android.R.string.cancel, [ ])
					.create()
					.show()
			} else {
				Log.d("url_loading", "Opening registered webapp for " + uri.toString)
				openWebapp(activity, webapps.get(0), uri)
			}
		}
	}

	override WebResourceResponse shouldInterceptRequest(WebView view, String url) {
		// Block 3rd party requests (i.e. scripts/iframes/etc. outside Google's domains)
		// and also any unencrypted connections
		val Uri uri = Uri.parse(url)
		val siteUrl = getHost(uri)
		var boolean isBlocked = false

		try {
			if (uri.path.contains(".")) {
				var media = #[
					// playlists
					".m3u8",".m3u",".pls",
					// video
					".mp4",".mpv",".mpeg",".webm",".vp9",".ogv",".mkv",".avi",".gifv",
					// audio
					".aac", ".ogg", ".mp3", ".m4a", ".nsv"
				].exists[ uri.path.endsWith(it) ]

				if (media) {
					Log.d("CAST", "Found media " + url)
					shareUrl(uri, "video/mpeg", -1l)
				} else {
					//Log.d("CAST", "skipping " + uri.toString)
				}
			} else {
				// check the content type for playable media
				async() [
					var con = new URL(url).openConnection() as HttpURLConnection
					con.setRequestMethod("HEAD")
					if (activity.settings.userAgent != null &&
							activity.settings.userAgent.trim().length > 0) {
						// User-agent may affect site redirects
						con.setRequestProperty("User-Agent", activity.settings.userAgent)
					}
					val ret = #[ con.getContentType(), con.getContentLengthLong(), con.getURL() ]
					con.inputStream.close()
					return ret
				].then[ List result |
					val contentType = result.get(0) as String
					val contentLength = result.get(1) as Long
					val url2 = result.get(2) as URL

					if (contentType?.startsWith("video/") || contentType?.startsWith("audio/")) {
						Log.d("CAST", result.toString() + ": " + url2)
						shareUrl(Uri.parse(url2.toString), contentType, contentLength)
					}
				].onError[ error |
					// ignore errors
					//Log.e("CAST", "error", error)
				].start()
			}
		} catch (Exception e) {
			Log.d("CAST", e.class.simpleName + " " + e.message)
		}

		if (isBlocked) {
			if (Debug.ON) Log.d("webclient", "Blocking " + url);
			blockedHosts.put(getRootDomain(url), true)
			return new WebResourceResponse("text/plain", "utf-8", new ByteArrayInputStream("[blocked]".getBytes()))
		}

		val cookieManager = CookieManager.instance
		if (Debug.COOKIE && siteUrl !== null) Log.d("cookie", "Cookies for " + siteUrl + ": " +
                cookieManager.getCookie(siteUrl.toString()))

		return super.shouldInterceptRequest(view, url)
	}

	// Get the host/domain from a URL or a host string.
	def public static String getHost(Uri uri, String defaultHost) {
		if (uri === null) return defaultHost
		var ret = uri.getHost()
		if (ret !== null) {
			return ret
		} else {
			return defaultHost
		}
	}

	// Get the host/domain from a URL or a host string.
	def public static String getHost(String url, String defaultHost) {
		if (url == null) return defaultHost
		try {
			if (url.indexOf("://") > 0) {
				return getHost(Uri.parse(url))
			} else {
				return getHost(Uri.parse("https://" + url))
			}
		} catch (Exception e) {
			Log.e("host", "Error parsing " + url, e)
			return defaultHost
		}
	}

	def public static String getHost(Uri uri) {
		var ret = getHost(uri, UNKNOWN_HOST)
		//Log.d("host", "Uri " + uri.toString() + " -> " + ret)
		return ret
	}

	def public static String getHost(String url) {
		var ret = getHost(url, UNKNOWN_HOST)
		//Log.d("host", "Url " + url + " -> " + ret)
		return ret
	}

	/** 
	 * Most blocked 3rd party domains are CDNs, so rather use root domain
	 * @param url
	 * @return
	 */
	def public static String getRootDomain(String url) {
		var String host = getHost(url)

		try {
			var String[] parts = host.split("\\.").reverseView()
			if (parts.length > 2) {
				// handle things like mobile.site.co.za vs www1.api.site.com
				if (parts.get(0).length == 2 && parts.get(1).length <= 3) {
					return '''«{parts.get(2)}».«{parts.get(1)}».«{parts.get(0)}»'''
				} else {
					return '''«{parts.get(1)}».«{parts.get(0)}»'''
				}
			} else if (parts.length > 1) {
				return '''«{parts.get(1)}».«{parts.get(0)}»'''
			} else {
				return host
			}
		} catch (Exception e) {
			// sometimes things don't quite work out
			return host
		}
	}

	override void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
		super.onReceivedError(view, errorCode, description, failingUrl)
		Toast.makeText(activity, description, Toast.LENGTH_LONG).show()
	}

	def void openWebapp(Webapp webapp, Uri uri) {
		openWebapp(activity, webapp, uri)
	}

	def static void openWebapp(Context activity, Webapp webapp, Uri uri) {
		var intent = new Intent(activity, typeof(WebAppActivity))
		intent.action = Intent.ACTION_VIEW
		intent.data = Uri.parse(uri.toString)
		BaseWebAppActivity.putWebappId(intent, webapp.id)
		BaseWebAppActivity.putFromShortcut(intent, false)
		activity.startActivity(intent)
	}

	/** 
	 * Parse the Uri and return an actual Uri to load. This will handle
	 * exceptions, like loading a URL
	 * that is passed in the "url" parameter, to bypass click-throughs, etc.
	 * @param uri
	 * @return
	 */
	def protected Uri getLoadUri(Uri uri) {
		if(uri === null) return uri // handle google news links to external sites directly
		try {
			if (uri.getQueryParameter("url") !== null) {
				return Uri.parse(uri.getQueryParameter("url"))
			}
		} catch (UnsupportedOperationException e) {
			// Not a hierarchical uri with a query parameter, like data:
			return uri
		}
		return uri
	}

	/** 
	 * Returns true if the  linked site is within the Webapp's domain
	 * @param uri
	 * @return
	 */
	def public static boolean isInSandbox(Uri uri, Set<String> domainUrls) {
		if("data".equals(uri.getScheme()) || "blob".equals(uri.getScheme())) return true
		var String host = uri.getHost()
		if (host == null) return true;

		for (String sites : domainUrls) {
			for (String site : sites.split(" ")) {
				if (site != null && host.toLowerCase().endsWith(site.toLowerCase())) {
					return true
				}

			}

		}
		return false
	}

	def protected boolean isInSandbox(Uri uri) {
		return isInSandbox(uri, domainUrls)
	}

	def Set<String> getBlockedHosts() {
		blockedHosts.keySet()
	}

	/** 
	 * Add domains to be unblocked
	 * @param unblock
	 */
	def void unblockDomains(Set<String> unblock) {
		for (String s : domainUrls) {
			unblock.add(s)
		}
		domainUrls = unblock
	}
}
