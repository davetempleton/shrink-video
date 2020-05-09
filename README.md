Make your video library take up less space.
===========================================

Introduction
------------

This script will traverse a directory recursively, find all video files ending with a certain set of extensions, compute a basic "quality" metric about its encoding, and if it is above a certain threshold, re-encode the video using HandBrakeCLI.

Given this script may take months to exit, depending how many and large the video files are present, state is maintained in several files. This script is meant for 1080p and smaller video files; it has not been optimized for 4K.

Note that the script makes some hard-coded choices you may disagree with, like converting all 1080p files to 720p and downmixing to stereo audio.

Usage
-----

You will need ruby, ffmpeg (for ffprobe), and HandBrakeCLI. On Ubuntu 16.04 and newer: `apt install ruby rbenv ruby-build bundler ffmpeg handbrake-cli`. On Fedora 30 or newer: ``. Rename the configuration file to `config.yml` after editing. The only parameters you MUST edit are `working_path` and `trash_path`.

The script can be run with an argument of a directory; otherwise, it will traverse the current directory looking for videos to encode. Multiple directories can be colon-separated. For example:

```ruby shrink-video.rb
ruby shrink-video.rb directory
ruby shrink-video.rb directory1:/directory2:~/Videos/Directory\ Three
```
