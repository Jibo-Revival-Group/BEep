#!/bin/bash
# Runs on the Android emulator: home screen, a robot's BEacon, and a conversion over SSH, against
# the stand-in robot (ci/fake-beacon.py on 8123, ci/fake-jibo-ssh.py on 2222) on the host, 10.0.2.2.
set -ex
APP=com.jiborevival.beep
adb install -r android/app/build/outputs/apk/stable/release/app-stable-release.apk
start() { adb shell am force-stop $APP; adb shell am start -W -n $APP/.MainActivity "$@"; }
shot() { sleep "$2"; adb exec-out screencap -p > "$1"; }
start --ez BEepStayHome true
shot android-home.png 6
start --ez BEepStayHome true --es BEepOpen 10.0.2.2 --es BEepPanel store
shot android-robot.png 20
adb shell uiautomator dump /sdcard/ui.xml >/dev/null && adb shell cat /sdcard/ui.xml > ui.xml
grep -q 'text="Store"' ui.xml
PM='echo "=== Step 1: Remount filesystem read-write ==="; sleep 2; echo "BEam and BEnch install complete."; echo "Mode change requires a reboot. Rebooting now..."'
start --ez BEepStayHome true --es BEepConvert 10.0.2.2 --ei BEepConvertPort 2222 --es BEepConvertPM "'$PM'"
shot android-convert.png 25
cat fakerun/commands.log
grep -q "5X1_PM_EXIT 0" fakerun/5x1-pm.log
