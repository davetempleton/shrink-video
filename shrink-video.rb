#!/usr/bin/env ruby

require_relative "shrink-video-conf"
require "fileutils"
require "shellwords"

abort "RUNNING file present" if File.exist?(runningpath)

Dir.chdir(ARGV[0]) unless ARGV.empty?
puts Dir.pwd

Dir.glob("**/*") do |filename|
    next if File.directory?(filename)
    next if File.exist?(File.join(File.dirname(filename),dotfileskip))
    next if File.exist?(File.join(File.expand_path("..", File.dirname(filename)),dotfileskip))
    next unless extensions.include? File.extname(filename).downcase
    next if File.readlines(checkedpath).grep(filename).any?
    next if Time.now - File.ctime(filename) < delaydays * 86400
    File.open(checkedpath,"a") { |f| f.puts(filename) }
    filename_s = Shellwords.escape(filename)
    bitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    width = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    height = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
    File.open(toobigbeforepath,"a") { |f| f.puts(filename) } if width > 1920
    quality = bitrate.to_f / ( width * height )
    if width > 1000
        ( quality < threshold ) && ( width < 1300 ) ? transcoding = false : ( transcoding = true; actthresh = threshold )
    else
        quality < ( threshold + 1.2 ) ? transcoding = false : ( transcoding = true; actthresh = threshold + 1.2 )
    end
    if transcoding
        File.new(runningpath,"w") { |f| f.puts(filename) }
        width > 1280 ? encodewidth = 1280 : encodewidth = width
        extbase = File.extname(filename)
        namebase = File.basename(filename, extbase)
        pathbase = File.dirname(filename)
        workingfilepath = File.join(workingpath, namebase, ".mkv")
        workingfilepath_s = Shellwords.escape(workingfilepath)
        `HandBrakeCLI -m -E ffaac -B 128 -6 stereo -X #{encodewidth} --loose-crop -e x264 -q 25 --x264-preset medium -s 1,2,3,4,5 -f mkv -i #{filename_s} -o #{workingfilepath_s}`
        ( File.open(errorpath,"a") { |f| f.puts("Handbrake error: #{filename}") }; next ) if `$?`.to_i != 0
        fulltrashdir = File.join(trashpath, pathbase)
        FileUtils.mkdir_p(fulltrashdir) unless File.directory?(fulltrashdir)
        begin
            FileUtils.mv(filename, File.join(fulltrashdir, namebase, extbase))
        rescue
            File.open(errorpath,"a") { |f| f.puts("Move to trash error: #{filename}") }
            next
        else
            FileUtils.mv(workingfilepath, filename)
        end
        File.open(transcodedpath,"a") { |f| f.puts(filename) }
        newbitrate = `ffprobe -v error -select_streams v:0 -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newwidth = `ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        newheight = `ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 #{filename_s}`.chomp.to_i
        if ( ( newbitrate.to_f / ( newwidth * newheight ) ) > actthresh ) || ( newbitrate > bitrate )
            File.open(toobigafterpath,"a") { |f| f.puts(filename) }
        end
        File.unlink(runningpath)
    else
        next
    end
end
