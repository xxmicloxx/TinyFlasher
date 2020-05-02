#!/bin/sh

sudo launchctl stop com.xxmicloxx.ImageWriterHelper
sudo launchctl remove com.xxmicloxx.ImageWriterHelper

sudo rm -f /Library/LaunchDaemons/com.xxmicloxx.ImageWriterHelper.plist
sudo rm -f /Library/PrivilegedHelperTools/com.xxmicloxx.ImageWriterHelper

echo "Uninstalled image helper"
