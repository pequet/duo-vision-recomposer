#!/bin/bash

# ██ ██   Duo-Vision Recomposer
# ██ ██   Version: 1.0.0
# ██ ██   Author: Benjamin Pequet
#         GitHub: https://github.com/pequet/duo-vision-recomposer/
#
# Purpose:
#   This script processes a video file shot in the "Duo-Vision" format
#   (e.g., the 1973 film 'Wicked, Wicked'), where two separate video streams
#   are presented side-by-side. It allows the user to extract these two
#   streams, crop them to remove any separating artifacts, and then recombine
#   them into a single, blended video with the original audio.
#
#   The script is designed for experimentation, allowing for precise control
#   over clip duration, start time, and cropping dimensions. All outputs are
#   saved to a unique, timestamped directory with a summary of the
#   parameters used for each run.
#
# Usage:
#   ./process_video.sh --help
#
# Dependencies:
#   - ffmpeg
#   - ffprobe
#
# Changelog:
#   1.0.0 - 2025-06-17 - Initial release.
#
# Support the Project:
#   - Buy Me a Coffee: https://buymeacoffee.com/pequet
#   - GitHub Sponsors: https://github.com/sponsors/pequet

# Strict mode
set -e
set -u
set -o pipefail

# --- Dependency Check ---
command -v ffmpeg >/dev/null 2>&1 || { echo >&2 "ffmpeg is not installed. Aborting."; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo >&2 "ffprobe is not installed. Aborting."; exit 1; }

# --- Usage Function ---
usage() {
    echo "NAME"
    echo "    process_video.sh - A tool to extract, blend, and process split-screen video files."
    echo ""
    echo "SYNOPSIS"
    echo "    ./process_video.sh <input_video_file> [OPTIONS]"
    echo ""
    echo "DESCRIPTION"
    echo "    This script processes a video file, assuming it contains two side-by-side video streams."
    echo "    It extracts the left and right streams into separate clips, creates a 'crisp' average"
    echo "    blend of the two, and adds the original audio back to the final video."
    echo ""
    echo "    All output files are saved into a new, unique, timestamped directory. A summary.txt"
    echo "    file is also created in that directory, logging all parameters used for the run."
    echo ""
    echo "ARGUMENTS"
    echo "    <input_video_file>"
    echo "        (Required) The full path to the source video file."
    echo ""
    echo "OPTIONS"
    echo "    --dir <path>"
    echo "        (Optional) The directory where the timestamped output folder will be created."
    echo "        Default: The current working directory."
    echo ""
    echo "    --start <seconds>"
    echo "        (Optional) The start time for the clip in seconds. Decimals are allowed."
    echo "        Default: 0 (the beginning of the video)."
    echo ""
    echo "    --length <seconds>"
    echo "        (Optional) The duration of the clip to process in seconds."
    echo "        Default: The full length of the video."
    echo ""
    echo "    --left-crop <w:h:x:y>"
    echo "        (Optional) The specific FFmpeg crop string for the left video stream."
    echo "        Default: Calculated as the exact left half of the video."
    echo ""
    echo "    --right-crop <w:h:x:y>"
    echo "        (Optional) The specific FFmpeg crop string for the right video stream."
    echo "        Default: Calculated as the exact right half of the video."
    echo ""
    echo "    --blend-mode <mode>"
    echo "        (Optional) The FFmpeg blend mode to use. Examples: average, multiply, screen, darken, lighten."
    echo "        Default: average."
    echo ""
    echo "    --contrast <value>"
    echo "        (Optional) The contrast value to apply to both clips before blending. 1.0 is no change."
    echo "        Default: 1.2."
    echo ""
    echo "    --no-audio"
    echo "        (Optional) Create a silent video file."
    echo ""
    echo "    --info"
    echo "        Displays information about the video file and exits."
    echo ""
    echo "    --help"
    echo "        Displays this help message and exits."
    echo ""
    echo "USAGE NOTES"
    echo "    - Codec Compatibility: For best results, ensure custom crop dimensions (width and"
    echo "      height) are even numbers. Odd-numbered dimensions can cause encoding artifacts"
    echo "      (e.g., a thin colored line at the video's edge), which may only appear"
    echo "      in snapshots and not during regular playback."
    exit 1
}

# --- Argument Parsing ---
if [ $# -eq 0 ] || [[ "$1" == "--help" ]]; then
    usage
fi

INPUT_FILE="$1"
shift # Shift positional arguments

# Default values
DEST_DIR="."
START_TIME="0"
LENGTH=""
LEFT_CROP=""
RIGHT_CROP=""
BLEND_MODE="average"
CONTRAST="1.2"
NO_AUDIO=false
USER_SPECIFIED_LENGTH=false # Flag to track if user set --length
INFO_MODE=false

# Parse named arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dir) DEST_DIR="$2"; shift ;;
        --start) START_TIME="$2"; shift ;;
        --length) LENGTH="$2"; USER_SPECIFIED_LENGTH=true; shift ;;
        --left-crop) LEFT_CROP="$2"; shift ;;
        --right-crop) RIGHT_CROP="$2"; shift ;;
        --blend-mode) BLEND_MODE="$2"; shift ;;
        --contrast) CONTRAST="$2"; shift ;;
        --no-audio) NO_AUDIO=true ;;
        --info) INFO_MODE=true ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Validate Input File ---
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found at '$INPUT_FILE'"
    exit 1
fi

# --- Probe Video File ---
echo "Probing '$INPUT_FILE'..."
DIMENSIONS_PROBE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
DURATION_PROBE=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")

VIDEO_WIDTH=$(echo "$DIMENSIONS_PROBE" | sed -n 1p)
VIDEO_HEIGHT=$(echo "$DIMENSIONS_PROBE" | sed -n 2p)
FRAME_RATE=$(echo "$DIMENSIONS_PROBE" | sed -n 3p)
VIDEO_DURATION=$DURATION_PROBE

# Calculate frame rate as a decimal for display, preventing all division-by-zero errors.
FPS=$(echo "$FRAME_RATE" | awk -F/ '{if (NF==2 && $2 > 0) printf "%.2f", $1/$2; else if (NF==1) print $1; else print "0.00"}')

echo "  - Dimensions: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}"
echo "  - Duration: ${VIDEO_DURATION}s"
echo "  - Frame Rate: ${FPS} fps"
echo "---"

# --- Info Mode ---
if [[ "$INFO_MODE" = true ]]; then
    echo "--- Video Info ---"
    echo "File: $INPUT_FILE"
    echo "Dimensions: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}"
    echo "Duration: ${VIDEO_DURATION}s"
    echo "Frame Rate: ${FPS} fps ($FRAME_RATE)"
    echo "------------------"
    exit 0
fi

# --- Set Defaults Based on Probe Data ---
if [ -z "$LENGTH" ]; then
    LENGTH=$VIDEO_DURATION
fi

if [ -z "$LEFT_CROP" ]; then
    LEFT_CROP="iw/2:ih:0:0"
fi

if [ -z "$RIGHT_CROP" ]; then
    RIGHT_CROP="iw/2:ih:iw/2:0"
fi

# --- Setup Output Directory and Summary ---
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
OUTPUT_DIR="$DEST_DIR/output_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

SUMMARY_FILE="$OUTPUT_DIR/summary.txt"
echo "--- Run Summary ---" > "$SUMMARY_FILE"
echo "Timestamp: $TIMESTAMP" >> "$SUMMARY_FILE"
echo "Input File: $INPUT_FILE" >> "$SUMMARY_FILE"
echo "Output Directory: $OUTPUT_DIR" >> "$SUMMARY_FILE"
echo "--- Parameters ---" >> "$SUMMARY_FILE"
echo "Start Time: ${START_TIME}s" >> "$SUMMARY_FILE"
echo "Length: ${LENGTH}s" >> "$SUMMARY_FILE"
echo "Left Crop: $LEFT_CROP" >> "$SUMMARY_FILE"
echo "Right Crop: $RIGHT_CROP" >> "$SUMMARY_FILE"
echo "Blend Mode: $BLEND_MODE" >> "$SUMMARY_FILE"
echo "Contrast: $CONTRAST" >> "$SUMMARY_FILE"
echo "No Audio: $NO_AUDIO" >> "$SUMMARY_FILE"

echo "Processing started. Output will be saved to: $OUTPUT_DIR"
cat "$SUMMARY_FILE"
echo "---"

# --- Define Output File Paths ---
AUDIO_FILE="$OUTPUT_DIR/master_audio.aac"
LEFT_CLIP="$OUTPUT_DIR/left_clip.mkv"
RIGHT_CLIP="$OUTPUT_DIR/right_clip.mkv"
MERGED_SILENT_VIDEO="$OUTPUT_DIR/merged_crisp_average.mkv"

# --- Construct Final Filename ---
FILENAME="FINAL_VIDEO"
if [[ "$NO_AUDIO" = true ]]; then
    FILENAME+="_silent"
fi
if [[ "$START_TIME" != "0" ]]; then
    FILENAME+="_start-${START_TIME}"
fi

if [[ "$USER_SPECIFIED_LENGTH" = true ]]; then
    FILENAME+="_length-${LENGTH}"
fi

FINAL_VIDEO="$OUTPUT_DIR/${FILENAME}.mkv"

# --- Execute FFmpeg Workflow ---

if [[ "$NO_AUDIO" = false ]]; then
    echo "Step 1: Extracting Audio..."
    ffmpeg -i "$INPUT_FILE" -ss "$START_TIME" -t "$LENGTH" -vn -y "$AUDIO_FILE"
fi

echo "Step 2: Extracting Left Clip..."
ffmpeg -i "$INPUT_FILE" -ss "$START_TIME" -t "$LENGTH" -filter:v "crop=$LEFT_CROP" -an -y "$LEFT_CLIP"

echo "Step 3: Extracting Right Clip..."
ffmpeg -i "$INPUT_FILE" -ss "$START_TIME" -t "$LENGTH" -filter:v "crop=$RIGHT_CROP" -an -y "$RIGHT_CLIP"

echo "Step 4: Blending silent clips..."
ffmpeg -i "$LEFT_CLIP" -i "$RIGHT_CLIP" -filter_complex "[0:v]eq=contrast=${CONTRAST}[lc];[1:v]eq=contrast=${CONTRAST}[rc];[lc][rc]blend=all_mode=${BLEND_MODE}" -y "$MERGED_SILENT_VIDEO"

if [[ "$NO_AUDIO" = false ]]; then
    echo "Step 5: Adding audio back..."
    ffmpeg -i "$MERGED_SILENT_VIDEO" -i "$AUDIO_FILE" -c:v copy -c:a copy -y "$FINAL_VIDEO"
else
    # If no audio, the merged silent video is the final video.
    mv "$MERGED_SILENT_VIDEO" "$FINAL_VIDEO"
fi

echo "---"
echo "Processing complete."
echo "Final video is at: $FINAL_VIDEO" 