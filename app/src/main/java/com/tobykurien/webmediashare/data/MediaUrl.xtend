package com.tobykurien.webmediashare.data

import org.eclipse.xtend.lib.annotations.Accessors
import android.net.Uri

@Accessors
class MediaUrl {
    Uri uri
    String contentType
    Long contentLength

    override toString() {
        contentType + ", " + contentLength + " bytes, " + uri.toString()
    }
}