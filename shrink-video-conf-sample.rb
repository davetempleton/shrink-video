#!/usr/bin/env ruby

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

