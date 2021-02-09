#!/bin/sh
if [ -e $1 ]; then
  FILTER="com.tobykurien.webmediashare"
else
  FILTER="$1"
fi

echo Compiling app...
./gradlew --no-daemon installDebug runApp |grep ERROR

adb logcat -c
adb logcat -v color -e "$FILTER" "*:D"
