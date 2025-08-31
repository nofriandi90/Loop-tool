#!/usr/bin/env bash
set -euo pipefail

# Load config
if [ -f "config.env" ]; then
  set -a
  source config.env
  set +a
fi

INPUT_DIR="input"
OUTPUT_DIR="output"
mkdir -p "$OUTPUT_DIR"

VID="$INPUT_DIR/${INPUT_VIDEO:-video.mp4}"
AUD="$INPUT_DIR/${INPUT_AUDIO:-music.mp3}"
PLAYLIST_TXT="$INPUT_DIR/playlist.txt"

DUR="${TARGET_DURATION_SECONDS:-1800}"
MODE="${AUDIO_MODE:-replace}"
VG="${VIDEO_AUDIO_GAIN_DB:--10}"
MG="${MUSIC_AUDIO_GAIN_DB:-0}"
PRESET="${X264_PRESET:-veryfast}"
CRF="${X264_CRF:-19}"

# Video filter opsional
VF=""
[ -n "${SCALE:-}" ] && VF="${VF:+$VF,}scale=$SCALE"
[ -n "${FPS:-}" ] && VF="${VF:+$VF,}fps=$FPS"
[ -n "$VF" ] && VF="-vf $VF"

# Cek video
[ ! -f "$VID" ] && { echo "Video tidak ditemukan: $VID"; exit 1; }

# Siapkan audio (support playlist)
if [ -f "$PLAYLIST_TXT" ]; then
  echo "Playlist terdeteksi..."
  TMP_LIST="tmp_audio_list.txt"
  mkdir -p tmp
  : > "$TMP_LIST"
  idx=0
  while IFS= read -r line || [ -n "$line" ]; do
    name=$(echo "$line" | tr -d '\r' | xargs)
    [ -z "$name" ] && continue
    idx=$((idx+1))
    wf="tmp/part_$idx.wav"
    ffmpeg -y -i "$INPUT_DIR/$name" -vn -ac 2 -ar 48000 -sample_fmt s16 "$wf"
    echo "file '$wf'" >> "$TMP_LIST"
  done < "$PLAYLIST_TXT"
  ffmpeg -y -f concat -safe 0 -i "$TMP_LIST" -c copy tmp/playlist_long.wav
  AUD="tmp/playlist_long.wav"
fi

OUT="$OUTPUT_DIR/output.mp4"

if [ "$MODE" = "replace" ]; then
  ffmpeg -y -stream_loop -1 -i "$VID" -stream_loop -1 -i "$AUD" \
    -t "$DUR" -shortest -map 0:v:0 -map 1:a:0 \
    -c:v libx264 $VF -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
    -c:a aac -b:a 192k -movflags +faststart "$OUT"
else
  ffmpeg -y -stream_loop -1 -i "$VID" -stream_loop -1 -i "$AUD" \
    -t "$DUR" -shortest \
    -filter_complex "[0:a]volume=${VG}dB[a0];[1:a]volume=${MG}dB[a1];[a0][a1]amix=inputs=2:normalize=0:duration=longest[mix]" \
    -map 0:v:0 -map "[mix]" \
    -c:v libx264 $VF -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
    -c:a aac -b:a 192k -movflags +faststart "$OUT"
fi
