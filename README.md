WebMediaShare Android app
=========================

An app to bookmark and browse media websites (e.g. Radio.net, SuperSport.com, etc.) for the purpose of sending media for casting to your TV, sharing, and/or downloading. It intercepts any requests on the current web page to audio or video files, and then pops up a share dialog to allow you to share it to another app.

This app pairs well with Kore Remote app for Kodi, allowing you to browse for media on your phone, and then share it to your TV via Kore Remote to a Kodi player. This works like ChromeCast, but without the need for ChromeCast hardware, or any dependencies to Google services. It also works for many other websites without the need for any specific support (e.g. apps or plugins for Kodi).

Forked from https://github.com/tobykurien/WebApps

Limitations
===========

- Cookies and referer information is lost when sharing a media URL, so it may not work if the server requires these
- Does not work well for sites like YouTube.com that stream their media in several chunked files
  - For YouTube in particular, use "Share URL" menu option to share to Kodi. Kodi will need the YouTube plugin installed.
