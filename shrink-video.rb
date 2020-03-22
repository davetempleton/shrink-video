#!/usr/bin/env ruby

require "fileutils"
require "shellwords"
require "yaml"

# Generate file path without extension
def no_ext(file)
    name = File.basename(file, File.extname(file))
    path = File.dirname(file)
    File.join(path, name)
end

# Valid x264 encoder speeds
speeds = ["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo"]

# Make sure HandBrakeCLI and FFmpeg are installed
abort "HandBrakeCLI not installed" if `which HandBrakeCLI`.empty?
abort "FFprobe (utility of FFmpeg) not installed" if `which ffprobe`.empty?

# Validate config and paths, and set up files
config_path = File.join(File.dirname(File.expand_path(__FILE__)), "config.yml")
abort "config.yml file does not exist in same folder as script" unless File.exist?(config_path)
config = YAML.load_file(config_path)
abort "Directory working_path does not exist" unless Dir.exist?(config['working_path'])
abort "Directory trash_path does not exist" unless Dir.exist?(config['trash_path'])
abort "dotfile_skip must begin with period" unless config['dotfile_skip'][0,1] == "."
abort "Thresholds must be numbers" unless ( config['threshold'].is_a? Numeric ) && ( config['threshold_sm'].is_a? Numeric )
abort "max_width must be a integer" unless config['max_width'].is_a? Integer
abort "max_width must be between 1000-10000, exclusive" unless ( config['max_width'].to_i > 1000 ) && ( config['max_width'].to_i < 10000 )
abort "delay_days should be non-negative number" unless ( config['delay_days'].is_a? Numeric ) && ( config['delay_days'].to_f >= 0 )
unless ( config['encode_quality'].is_a? Integer ) && ( config['encode_quality'] >= 18 ) && ( config['encode_quality'] <= 28 )
    abort "encode_quality must be an integer between 18-28, inclusive"
end
abort ("Not a valid x264 encoder speed; must be one of:\n" + speeds.to_s) unless speeds.include? config['speed']
unless config['extensions'].all?{ |ext| ext[0,1] == "." } && config['mandatory_encode'].all?{ |ext| ext[0,1] == "." }
    abort "All extensions must begin with period"
end
config['extensions'].each { |ext| ext.downcase! }
config['mandatory_encode'].each { |ext| ext.downcase! }
config['mandatory_encode'].each do |ext|
    abort "All extensions that must be mandatorily encoded must also be in the extensions array" unless config['extensions'].include? ext
end
FileUtils.touch(config['checked_path']) unless File.exist?(config['checked_path'])
FileUtils.touch(config['error_path']) unless File.exist?(config['error_path'])

# Do not run if already running or exited with uncaught exception
abort "RUNNING file present" if File.exist?(config['running_path'])

# Create RUNNING file, print start message, initialize counter
FileUtils.touch(config['running_path'])
puts "Starting #{Time.now}"
counter = 0

# Run from current directory if argument is not passed
Dir.chdir(ARGV[0]) unless ARGV.empty?
puts Dir.pwd

# Traverse directory tree recursively
Dir.glob("**/*") do |filename|
    
    filename.chomp!
    # Skip if file doesn't exist (happens when files deleted during long-running script)
    next unless File.exist?(filename)
    # Skip if not a file
    next if File.directory?(filename)
    # Skip if dotfile_skip in current dir
    next if File.exist?(File.join(File.dirname(filename), config['dotfile_skip']))
    # Skip if dotfile_skip in parent dir
    next if File.exist?(File.join(File.expand_path("..", File.dirname(filename)), config['dotfile_skip']))
    # Skip if file doesn't have required extension
    next unless config['extensions'].include?(File.extname(filename).downcase)
    # Skip if created in delay_days
    next if Time.now - File.ctime(filename) < config['delay_days'].to_f * 86400
    
    # Skip if already in checked list
    in_checked = false
    filename_no_ext = no_ext(filename)
    File.readlines(config['checked_path']).each do |line|
        in_checked = true if filename_no_ext == no_ext(line)
    end
    next if in_checked

    # Escape filename for security
    filename_s = Shellwords.escape(filename)
    
    # Prepare to move input file into the trash
    full_trash_dir = File.join(config['trash_path'], File.dirname(filename))
    FileUtils.mkdir_p(full_trash_dir) unless File.directory?(full_trash_dir)
    
    # Trash input file if there aren't both audio and video streams
    input_streams = `ffprobe -v 0 -show_entries stream=codec_type #{filename_s}`
    input_audio_streams = input_streams.scan(/codec_type=audio/).count
    input_video_streams = input_streams.scan(/codec_type=video/).count
    if ( input_audio_streams < 1 ) || ( input_video_streams < 1 )
        begin
            # Move input file to trash folder
            FileUtils.mv(filename, File.join(full_trash_dir, File.basename(filename)))
            File.open(config['error_path'],"a") { |f| f.puts("Input doesn't have audio and video streams, deleted: #{filename}") }
        rescue
            # If move fails, log error
            File.open(config['error_path'],"a") { |f| f.puts("Move to trash error (before transcoding): #{filename}") }
        end
        next
    end
    
    # Add to checked list
    File.open(config['checked_path'],"a") { |f| f.puts(filename) }
    
    # Find input video stats
    bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    codec = `ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp
    
    # Calculate arbitrary quality metric, and decide if to transcode
    old_quality = bitrate.to_f / ( width * height )
    if width > 1000
        # Transcode if too high quality, or if bigger than max_width
        threshold = config['threshold'].to_f
        ( old_quality < threshold ) && ( width <= config['max_width'].to_i ) ? transcoding = false : transcoding = true
    else
        # Video below 720p has more information per pixel and needs higher threshold
        threshold = config['threshold_sm'].to_f
        old_quality < threshold ? transcoding = false : transcoding = true
    end
    
    # Transcode if in mandatory_encode list or HEVC
    transcoding = true if config['mandatory_encode'].include?(File.extname(filename).downcase)
    transcoding = true if codec == "hevc"
    
    # Transcoding and file management
    if transcoding
        
        # Write filename to RUNNING file
        File.open(config['running_path'],"w") { |f| f.puts(filename) }
        puts "Transcoding: #{filename}"
        
        # Set output video width. Max video size is 720p
        width > config['max_width'].to_i ? encode_width = config['max_width'].to_i : encode_width = width
        
        extbase = File.extname(filename)
        namebase = File.basename(filename, extbase)
        pathbase = File.dirname(filename)
        
        # Create paths for output file temporary and final locations
        working_file_path = File.join(config['working_path'], namebase) + ".mkv"
        filename_out = File.join(pathbase, namebase) + ".mkv"
        # Escape filename for security
        working_file_path_s = Shellwords.escape(working_file_path)
        filename_out_s = Shellwords.escape(filename_out)
        
        # HandBrakeCLI command below. Two channel AAC audio only, x264 encoder, passthrough subtitles, MKV container.
        handbrake_cmd = "HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encode_width} --loose-crop -e x264 -q #{config['encode_quality']} --x264-preset #{config['speed']} -s 1,2,3,4,5 -f mkv -i #{filename_s} -o #{working_file_path_s}"
        `#{handbrake_cmd} > /dev/null 2>&1`
=begin
        # Move on if HandBrakeCLI has non-zero exit code, deleting any output file
        unless $?.success?
            File.open(config['error_path'],"a") { |f| f.puts("Handbrake error: #{filename}") }
            File.unlink(working_file_path) if File.exist?(working_file_path)
            File.open(config['running_path'],"w") { |f| f.puts("") }
            next
        end
=end
        # Move on if no output file found
        unless File.exist?(working_file_path)
            File.open(config['error_path'],"a") { |f| f.puts("No output file found: #{filename}") }
            File.open(config['running_path'],"w") { |f| f.puts("") }
            next
        end
        
        # If output under 1MiB in size, try again with mp4 container
        output_size = File.size(working_file_path).to_f / 2**20
        if output_size < 1
            File.unlink(working_file_path)
            
            # Create paths for output file temporary and final locations, but with mp4 extension
            working_file_path = File.join(config['working_path'], namebase) + ".mp4"
            filename_out = File.join(pathbase, namebase) + ".mp4"
            # Escape filename for security
            working_file_path_s = Shellwords.escape(working_file_path)
            filename_out_s = Shellwords.escape(filename_out)
            
            # Identical HandBrakeCLI command, only with mp4 container, and "web-optimized" file (option for mp4 only)
            handbrake_cmd = "HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encode_width} --loose-crop -e x264 -q #{config['encode_quality']} --x264-preset #{config['speed']} -s 1,2,3,4,5 -f av_mp4 -O -i #{filename_s} -o #{working_file_path_s}"
            `#{handbrake_cmd} > /dev/null 2>&1`
            
            # Move on if output still under 1MiB in size
            output_size = File.size(working_file_path).to_f / 2**20
            if output_size < 1
                File.unlink(working_file_path)
                File.open(config['error_path'],"a") { |f| f.puts("Output under 1MiB, aborted: #{filename}") }
                File.open(config['running_path'],"w") { |f| f.puts("") }
                next
            end
        end
        
        # Move on if output file doesn't have at least one video and audio stream
        output_streams = `ffprobe -v 0 -show_entries stream=codec_type #{working_file_path_s}`
        output_audio_streams = output_streams.scan(/codec_type=audio/).count
        output_video_streams = output_streams.scan(/codec_type=video/).count
        if ( output_audio_streams < 1 ) || ( output_video_streams < 1 )
            File.unlink(working_file_path)
            File.open(config['error_path'],"a") { |f| f.puts("Output doesn't have audio and video streams, aborted: #{filename}") }
            File.open(config['running_path'],"w") { |f| f.puts("") }
            next
        end
        
        # Move input file to the trash, and output file to where the input file was
        begin
            # Move input file to trash folder
            FileUtils.mv(filename, File.join(full_trash_dir, File.basename(filename)))
        rescue
            # If move fails, log error and move on, leaving output file in temporary folder
            File.open(config['error_path'],"a") { |f| f.puts("Move to trash error: #{filename}") }
            File.open(config['running_path'],"w") { |f| f.puts("") }
            next
        else
            # Only move output file from temporary folder if input file was moved successfully
            FileUtils.mv(working_file_path, filename_out)
        end
        
        # Add file to transcoded list, increment counter
        File.open(config['transcoded_path'],"a") { |f| f.puts(filename) }
        counter += 1
        
        # Find output video stats
        new_bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        new_width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        new_height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        
        # Log if output file is still above threshold, or if we managed to create a larger file
        new_quality = new_bitrate.to_f / ( new_width * new_height )
        if ( new_quality > threshold ) || ( new_bitrate > bitrate )
            File.open(config['too_big_after_path'],"a") { |f| f.puts("#{new_quality.round(1)}: #{filename}") }
        end
        
        # Delete RUNNING file
        File.open(config['running_path'],"w") { |f| f.puts("") }
        
    end
    
end

# Delete RUNNING file
File.unlink(config['running_path'])

# Print exit information
puts "Transcoded #{counter} file(s)."
puts "Exiting #{Time.now}"
