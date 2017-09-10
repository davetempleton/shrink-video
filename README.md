This script will traverse a directory recursively, find all video files ending with a certain set of extensions, compute a basic "quality" metric about its encoding, and if it is above a certain threshold, re-encode the video using HandBrakeCLI.

Given this script may take months to exit, depending how many and large the video files are present, state is maintained in several files. This script is meant for 1080p and smaller video files; it has not been optimized for 4K.

You will need ruby, ffmpeg (for ffprobe), and HandBrakeCLI.
