#!/usr/bin/env ruby

# Rename this file to: shrink-video-conf.rb
# Example paths below. Please change them to suit your needs.
# Paths in /video-volume are where the video files will be shuffled around,
# and should be the same file system to avoid wait times for moving files.

# ACCESSORY FILES:
def runningpath() "RUNNING" end
def checkedpath() "checked" end
def toobigbeforepath() "toobigbefore" end
def toobigafterpath() "toobigafter" end
def workingpath() "/video-volume/Library/shrink-video" end
def errorpath() "errors" end
def trashpath() "/video-volume/shrink-video-trash" end
def transcodedpath() "transcoded" end
def dotfileskip() ".donotshrink" end

# VARIABLES/TUNABLES
def extensions() [".mkv", ".mp4", ".m4v", ".avi", ".mpg"] end
def threshold() "2.4".to_f end # Bitrate in b/s divided by total pixels
def delaydays() 7 end

