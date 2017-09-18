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

# Validate config and paths, and set up files
script_dir = File.dirname(File.expand_path(__FILE__))
config_path = File.join(script_dir, "config.yml")
abort "config.yml file does not exist in same folder as script" unless File.exist?(config_path)
config = YAML.load_file(config_path)
abort "Directory working_path does not exist" unless Dir.exist?(config['working_path'])
abort "Directory trash_path does not exist" unless Dir.exist?(config['trash_path'])
abort "dotfile_skip must begin with period" unless config['dotfile_skip'][0,1] == "."
abort "All extensions must begin with period" unless config['extensions'].all?{ |ext| ext[0,1] == "." }
FileUtils.touch(config['checked_path']) unless File.exist?(config['checked_path'])
FileUtils.touch(config['error_path']) unless File.exist?(config['error_path'])

# Do not run if already running or exited with uncaught exception
abort "RUNNING file present" if File.exist?(config['running_path'])

# Run from current directory if argument is not passed
Dir.chdir(ARGV[0]) unless ARGV.empty?
puts Dir.pwd

# Traverse directory tree recursively
Dir.glob("**/*") do |filename|
    
    filename = filename.chomp
    # Skip if not a file
    next if File.directory?(filename)
    # Skip if dotfile_skip in current dir
    next if File.exist?(File.join(File.dirname(filename), config['dotfile_skip']))
    # Skip if dotfile_skip in parent dir
    next if File.exist?(File.join(File.expand_path("..", File.dirname(filename)), config['dotfile_skip']))
    # Skip if file doesn't have required extension
    next unless config['extensions'].include?(File.extname(filename).downcase)
    # Skip if created in delay_days
    next if Time.now - File.ctime(filename) < config['delay_days'].to_i * 86400
    
    # Skip if already in checked list
    in_checked = false
    filename_no_ext = no_ext(filename)
    File.readlines(config['checked_path']).each do |line|
        in_checked = true if filename_no_ext == no_ext(line)
    end
    next if in_checked
    
    # Add to checked list
    File.open(config['checked_path'],"a") { |f| f.puts(filename) }
    
    # Escape filename for security
    filename_s = Shellwords.escape(filename)
    
    # Find input video stats
    bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    
    # Script not meant to handle video bigger than 1080p
    File.open(config['too_big_before_path'],"a") { |f| f.puts(filename) } if width > 1920
    
    # Calculate arbitrary quality metric, and decide if to transcode
    quality = bitrate.to_f / ( width * height )
    if width > 1000
        # Transcode if too high quality, or if bigger than 720p
        adjusted_threshold = config['threshold'].to_f
        ( quality < adjusted_threshold ) && ( width < 1300 ) ? transcoding = false : transcoding = true
    else
        # Video below 720p has more information per pixel and needs higher threshold
        adjusted_threshold = config['threshold'].to_f + 1.2
        quality < adjusted_threshold ? transcoding = false : transcoding = true
    end
    
    # Transcoding and file management
    if transcoding
        
        # Create RUNNING file
        File.open(config['running_path'],"w") { |f| f.puts(filename) }
        
        # Set output video width. Max video size is 720p
        width > 1280 ? encode_width = 1280 : encode_width = width
        
        extbase = File.extname(filename)
        namebase = File.basename(filename, extbase)
        pathbase = File.dirname(filename)
        
        # Create paths for output file temporary and final locations
        working_file_path = File.join(config['working_path'], namebase) + ".mkv"
        filename_out = File.join(pathbase, namebase) + ".mkv"
        # Escape filename for security
        working_file_path_s = Shellwords.escape(working_file_path)
        filename_out_s = Shellwords.escape(filename_out)
        
        # HandBrakeCLI command below. Two channel AAC audio only, x264 encoder, quality level 25, passthrough subtitles, MKV container.
        handbrake_cmd = "HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encode_width} --loose-crop -e x264 -q 25 --x264-preset medium -s 1,2,3,4,5 -f mkv -i #{filename_s} -o #{working_file_path_s}"
        `#{handbrake_cmd}`
        
        # Move on if HandBrakeCLI has non-zero exit code
        if `$?`.to_i != 0
            File.open(config['error_path'],"a") { |f| f.puts("Handbrake error: #{filename}") }
            File.unlink(config['running_path'])
            next
        end
        
        # Move on if under 1MiB in size
        output_size = File.size(working_file_path).to_f / 2**20
        if output_size < 1
            File.open(config['error_path'],"a") { |f| f.puts("Output under 1MiB, aborted: #{filename}") }
            File.unlink(working_file_path)
            File.unlink(config['running_path'])
            next
        end
        
        # Prepare to move input file into the trash
        full_trash_dir = File.join(config['trash_path'], pathbase)
        FileUtils.mkdir_p(full_trash_dir) unless File.directory?(full_trash_dir)
        
        # Move input file to the trash, and output file to where the input file was
        begin
            # Move input file to trash folder
            FileUtils.mv(filename, File.join(full_trash_dir, File.basename(filename)))
        rescue
            # If move fails, log error and move on, leaving output file in temporary folder
            File.open(config['error_path'],"a") { |f| f.puts("Move to trash error: #{filename}") }
            File.unlink(config['running_path'])
            next
        else
            # Only move output file from temporary folder if input file was moved successfully
            FileUtils.mv(working_file_path, filename_out)
        end
        
        # Add file to transcoded list
        File.open(config['transcoded_path'],"a") { |f| f.puts(filename) }
        
        # Find output video stats
        new_bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        new_width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        new_height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_out_s}`.chomp.to_i
        
        # Log if output file is still above threshold, or if we managed to create a larger file
        if ( ( new_bitrate.to_f / ( new_width * new_height ) ) > adjusted_threshold ) || ( new_bitrate > bitrate )
            File.open(config['too_big_after_path'],"a") { |f| f.puts(filename) }
        end
        
        # Delete RUNNING file
        File.unlink(config['running_path'])
        
    end
    
end
