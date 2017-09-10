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
    
    # Skip if not a file
    next if File.directory?(filename)
    # Skip if dotfileskip in current dir
    next if File.exist?(File.join(File.dirname(filename),dotfileskip))
    # Skip if dotfileskip in parent dir
    next if File.exist?(File.join(File.expand_path("..", File.dirname(filename)),dotfileskip))
    # Skip if file doesn't have required extension
    next unless extensions.include? File.extname(filename).downcase
    # Skip if already in checked list
    next if File.readlines(checkedpath).grep(filename).any?
    # Skip if created in last week
    next if Time.now - File.ctime(filename) < delaydays * 86400
    
    # Add to checked list
    File.open(checkedpath,"a") { |f| f.puts(filename) }
    
    # Escape filename for security
    filename_s = Shellwords.escape(filename)
    
    # Find input video stats
    bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    
    # Script not meant to handle video bigger than 1080
    File.open(toobigbeforepath,"a") { |f| f.puts(filename) } if width > 1920
    
    # Calculate arbitrary quality metric, and decide if to transcode
    quality = bitrate.to_f / ( width * height )
    if width > 1000
        # Transcode if too high quality, or if bigger than 720p
        ( quality < threshold ) && ( width < 1300 ) ? transcoding = false : ( transcoding = true; actthresh = threshold )
    else
        # Video below 720p has more information per pixel and needs higher threshold
        quality < ( threshold + 1.2 ) ? transcoding = false : ( transcoding = true; actthresh = threshold + 1.2 )
    end
    
    # Transcoding step
    if transcoding
        
        # Create RUNNING file
        File.open(runningpath,"w") { |f| f.puts(filename) }
        
        # Set output video width. Max video size is 720p
        width > 1280 ? encodewidth = 1280 : encodewidth = width
        
        extbase = File.extname(filename)
        namebase = File.basename(filename, extbase)
        pathbase = File.dirname(filename)
        
        # Output file is stored here temporarily
        workingfilepath = File.join(workingpath, namebase) + ".mkv"
        # Escape filename for security
        workingfilepath_s = Shellwords.escape(workingfilepath)
        
        # HandBrakeCLI command below. Two channel AAC audio only, x264 encoder, quality level 25, passthrough subtitles, MKV container.
        handbrakecmd = "HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encodewidth} --loose-crop -e x264 -q 25 --x264-preset medium -s 1,2,3,4,5 -f mkv -i #{filename_s} -o #{workingfilepath_s}"
        `#{handbrakecmd}`
        
        # Move on if HandBrakeCLI has non-zero exit code
        if `$?`.to_i != 0
            File.open(errorpath,"a") { |f| f.puts("Handbrake error: #{filename}") }
            File.unlink(runningpath)
            next
        end
        
        # Prepare to move input file into the trash
        fulltrashdir = File.join(trashpath, pathbase)
        FileUtils.mkdir_p(fulltrashdir) unless File.directory?(fulltrashdir)
        
        # Move input file to the trash, and output file to where the input file was
        begin
            # Move input file to trash folder
            FileUtils.mv(filename, File.join(fulltrashdir, File.basename(filename)))
        rescue
            # If move fails, log error and move on, leaving output file in temporary folder
            File.open(errorpath,"a") { |f| f.puts("Move to trash error: #{filename}") }
            File.unlink(runningpath)
            next
        else
            # Only move output file from temporary folder if input file was moved successfully
            FileUtils.mv(workingfilepath, filename)
        end
        
        # Add file to transcoded list
        File.open(transcodedpath,"a") { |f| f.puts(filename) }
        
        # Find output video stats
        newbitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newwidth = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newheight = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        
        # Log if output file is still above threshold, or if we managed to create a larger file
        if ( ( newbitrate.to_f / ( newwidth * newheight ) ) > actthresh ) || ( newbitrate > bitrate )
            File.open(toobigafterpath,"a") { |f| f.puts(filename) }
        end
        
        # Delete RUNNING file
        File.unlink(runningpath)
    end
end
