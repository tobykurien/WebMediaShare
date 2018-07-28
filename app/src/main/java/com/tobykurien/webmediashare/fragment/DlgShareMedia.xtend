package com.tobykurien.webmediashare.fragment

import android.support.v4.app.DialogFragment
import org.xtendroid.annotations.AndroidDialogFragment
import com.tobykurien.webmediashare.R
import android.support.v7.app.AlertDialog
import android.net.Uri
import com.tobykurien.webmediashare.webviewclient.WebClient
import android.os.Bundle
import java.util.List
import com.tobykurien.webmediashare.data.MediaUrl
import android.content.Intent
import android.util.Log
import com.tobykurien.webmediashare.adapter.MediaUrlsAdapter
import android.content.Context
import android.support.v4.content.LocalBroadcastManager
import android.content.IntentFilter

@AndroidDialogFragment class DlgShareMedia extends DialogFragment {
    val List<MediaUrl> mediaUrls
    var MediaUrlsAdapter adapter = null
    var MediaUrl selectedMediaUrl = null

    val mediaUrlReceiver = new android.content.BroadcastReceiver() {
        override onReceive(Context context, Intent intent) {
            adapter?.notifyDataSetChanged()
        }
    }

    new () {
        super()
        mediaUrls = null
        if (true) throw new IllegalAccessException("Use the contructor with mediaUrls")
    }

    new(List<MediaUrl> inMediaUrls) {
        super()
        this.mediaUrls = inMediaUrls
    }

    /**
     * Create a dialog using the AlertDialog Builder, but our custom layout
     */
    override onCreateDialog(Bundle instance) {
        adapter = new MediaUrlsAdapter(activity, mediaUrls)
        selectedMediaUrl = mediaUrls.get(0)

        new AlertDialog.Builder(activity)
            .setTitle(R.string.title_share_media)
            .setSingleChoiceItems(adapter, 0, [a, b|
                selectedMediaUrl = mediaUrls.get(b)
            ])
            .setPositiveButton(R.string.btn_share_url, null) // to avoid it closing dialog
            .setNeutralButton(R.string.btn_share_stream,null)
            .create()
    }

    override onStart() {
        super.onStart()

        // register to listen for media URL broadcasts
        LocalBroadcastManager.getInstance(activity).registerReceiver(mediaUrlReceiver,
            new IntentFilter(WebClient.MEDIA_URL_FOUND))

        Log.d("CAST", mediaUrls.toString)
        if (mediaUrls == null || mediaUrls.length == 0) {
            dismiss()
            return
        }

        val button1 = (dialog as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE)
        button1.setOnClickListener [
            val i = new Intent(Intent.ACTION_SEND);
            i.setType("text/plain")
            i.putExtra(Intent.EXTRA_TEXT, selectedMediaUrl.uri.toString());
            i.putExtra(Intent.EXTRA_SUBJECT, selectedMediaUrl.uri.host);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            var chooser = Intent.createChooser(i, selectedMediaUrl.uri.host)
            if (i.resolveActivity(activity.getPackageManager()) != null) {
                activity.startActivity(chooser);
            }
        ]

        val button2 = (dialog as AlertDialog).getButton(AlertDialog.BUTTON_NEUTRAL)
        button2.setOnClickListener [
            val i = new Intent(Intent.ACTION_SEND);
            i.setType(selectedMediaUrl.contentType)
            i.putExtra(Intent.EXTRA_STREAM, selectedMediaUrl.uri);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            var chooser = Intent.createChooser(i, selectedMediaUrl.uri.host)
            if (i.resolveActivity(activity.getPackageManager()) != null) {
                activity.startActivity(chooser);
            }
        ]
    }

    override onStop() {
        LocalBroadcastManager.getInstance(activity).unregisterReceiver(mediaUrlReceiver)

        super.onStop()
    }


}
