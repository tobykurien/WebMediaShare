package com.tobykurien.webmediashare.adapter

import org.xtendroid.adapter.AndroidAdapter
import java.util.List
import com.tobykurien.webmediashare.data.MediaUrl
import android.view.View
import android.view.ViewGroup
import org.xtendroid.adapter.AndroidViewHolder
import com.tobykurien.webmediashare.R

@AndroidAdapter class MediaUrlsAdapter {
    List<MediaUrl> mediaUrls

    /**
     * ViewHolder class to save references to UI widgets in each row
     */
    @AndroidViewHolder(R.layout.row_media_url) static class ViewHolder {
    }

    override getView(int row, View cv, ViewGroup parent) {
        var vh = ViewHolder.getOrCreate(context, cv, parent)
        var mediaUrl = getItem(row)
        vh.name.text = mediaUrl.uri.host
        vh.url.text = mediaUrl.getContentType + " " + mediaUrl.uri.path

        vh.view
    }

}