package com.tobykurien.webmediashare.fragment

import android.preference.PreferenceFragment
import android.os.Bundle
import com.tobykurien.webmediashare.R

class PreferencesFragment extends PreferenceFragment {
   
   override onActivityCreated(Bundle savedInstanceState) {
      super.onActivityCreated(savedInstanceState)
      addPreferencesFromResource(R.xml.settings)
   }
   
}