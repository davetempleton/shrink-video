#!/usr/bin/env ruby

require_relative "shrink-video-conf"
require "fileutils"
require "shellwords"

# Do not run if already running or exited with exception
abort "RUNNING file present" if File.exist?(runningpath)

# Run from current directory if argument is not passed
Dir.chdir(ARGV[0]) unless ARGV.empty?
puts Dir.pwd

Dir.glob("**/*") do |filename|
    next if File.directory?(filename) # Skip if not a file
    next if File.exist?(File.join(File.dirname(filename),dotfileskip)) # Skip if dotfileskip in current dir
    next if File.exist?(File.join(File.expand_path("..", File.dirname(filename)),dotfileskip)) # Skip if dotfileskip in parent dir
    next unless extensions.include? File.extname(filename).downcase # Skip if file doesn't have required extension
    next if File.readlines(checkedpath).grep(filename).any? # Skip if already in checked list
    next if Time.now - File.ctime(filename) < delaydays * 86400 # Skip if created in last week
    File.open(checkedpath,"a") { |f| f.puts(filename) } # Add to checked list
    filename_s = Shellwords.escape(filename) # Escape filename for security
    bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    File.open(toobigbeforepath,"a") { |f| f.puts(filename) } if width > 1920 # Script not meant to handle video bigger than 1080p
    quality = bitrate.to_f / ( width * height ) # Calculate arbitrary quality metric
    if width > 1000
        # Transcode if too high quality, or if bigger than 720p
        ( quality < threshold ) && ( width < 1300 ) ? transcoding = false : ( transcoding = true; actthresh = threshold )
    else
        # Video below 720p has more information per pixel and needs higher threshold
        quality < ( threshold + 1.2 ) ? transcoding = false : ( transcoding = true; actthresh = threshold + 1.2 )
    end
    if transcoding
        File.new(runningpath,"w") { |f| f.puts(filename) } # Create RUNNING file
        width > 1280 ? encodewidth = 1280 : encodewidth = width # Max video size is 720p
        extbase = File.extname(filename)
        namebase = File.basename(filename, extbase)
        pathbase = File.dirname(filename)
        workingfilepath = File.join(workingpath, namebase, ".mkv") # Temporary file path
        workingfilepath_s = Shellwords.escape(workingfilepath) # Escape for safety
        # HandBrakeCLI command below. Two channel AAC audio only, x264 encoder, quality level 25, passthrough subtitles, MKV container.
        `HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encodewidth} --loose-crop -e x264 -q 25 --x264-preset medium -s 1,2,3,4,5 -f mkv -i #{filename_s} -o #{workingfilepath_s}`
        ( File.open(errorpath,"a") { |f| f.puts("Handbrake error: #{filename}") }; next ) if `$?`.to_i != 0 # Move on if HandBrakeCLI has non-zero exit code
        fulltrashdir = File.join(trashpath, pathbase)
        FileUtils.mkdir_p(fulltrashdir) unless File.directory?(fulltrashdir) # Make folder in trash folder to move old file to
        begin
            FileUtils.mv(filename, File.join(fulltrashdir, namebase, extbase)) # Move old file to trash folder
        rescue
            File.open(errorpath,"a") { |f| f.puts("Move to trash error: #{filename}") } # Log error
            next
        else
            FileUtils.mv(workingfilepath, filename) # Only move new file from temporary location if move of old file works
        end
        File.open(transcodedpath,"a") { |f| f.puts(filename) } # Add file to transcoded list
        newbitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newwidth = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newheight = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        if ( ( newbitrate.to_f / ( newwidth * newheight ) ) > actthresh ) || ( newbitrate > bitrate )
            File.open(toobigafterpath,"a") { |f| f.puts(filename) } # Log if file still is above quality threshold after transcoding
        end
        File.unlink(runningpath) # Delete RUNNING file
    end
end
