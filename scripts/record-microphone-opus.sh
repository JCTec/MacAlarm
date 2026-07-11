#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

BITRATE="${MIC_BITRATE:-32k}"
SAMPLE_RATE="${MIC_SAMPLE_RATE:-16000}"
CHANNELS="${MIC_CHANNELS:-1}"
DEVICE="${MIC_DEVICE:-}"
OUTPUT_DIR="${MIC_OUTPUT_DIR:-$PWD/recordings/audio}"
SEGMENT_SECONDS="${MIC_SEGMENT_SECONDS:-86400}"
BACKEND="${MIC_BACKEND:-}"
LIST_DEVICES=0
KEEP_AWAKE=0

usage() {
  cat <<USAGE
Usage:
  $SCRIPT_NAME [options]

Records a connected microphone to compact Ogg Opus until you press Ctrl-C.

Options:
  -d, --device VALUE       Microphone device index or name. macOS defaults to 0.
  -o, --output-dir DIR     Directory for .opus files. Default: ./recordings/audio
  -b, --bitrate RATE       Opus bitrate. Default: 32k
  -r, --sample-rate HZ     Capture sample rate. Default: 16000
  -c, --channels COUNT     Audio channels. Default: 1
      --segment-minutes N  Rotate output files every N minutes.
      --segment-hours N    Rotate output files every N hours.
      --segment-days N     Rotate output files every N days. Default: 1
      --segment-seconds N  Rotate output files every N seconds.
      --no-segment         Record to one timestamped .opus file.
      --keep-awake         macOS only: run ffmpeg through caffeinate.
      --backend NAME       Linux only: pulse or alsa. Auto-detected by default.
      --list-devices       Show audio input devices and exit.
  -h, --help               Show this help.

Examples:
  ./$SCRIPT_NAME --list-devices
  ./$SCRIPT_NAME --device 0
  ./$SCRIPT_NAME --device "MacBook Pro Microphone" --segment-days 1
  ./$SCRIPT_NAME --device 0 --keep-awake --output-dir "\$HOME/Audio"

Environment overrides:
  MIC_DEVICE, MIC_OUTPUT_DIR, MIC_BITRATE, MIC_SAMPLE_RATE, MIC_CHANNELS,
  MIC_SEGMENT_SECONDS, MIC_BACKEND

Notes:
  - Requires ffmpeg with libopus support.
  - On macOS, the terminal app running this script needs Microphone permission.
  - First Ctrl-C finalizes the current .opus file; a second interrupt force-stops.
  - For power loss or crashes, use shorter segments to limit the active file.
USAGE
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  local flag="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    fail "$flag requires a value"
  fi
}

require_positive_int() {
  local flag="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -eq 0 ]]; then
    fail "$flag must be a positive integer"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      require_value "$1" "${2:-}"
      DEVICE="$2"
      shift 2
      ;;
    -o|--output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -b|--bitrate)
      require_value "$1" "${2:-}"
      BITRATE="$2"
      shift 2
      ;;
    -r|--sample-rate)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      SAMPLE_RATE="$2"
      shift 2
      ;;
    -c|--channels)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      CHANNELS="$2"
      shift 2
      ;;
    --segment-minutes)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      SEGMENT_SECONDS=$((10#$2 * 60))
      shift 2
      ;;
    --segment-hours)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      SEGMENT_SECONDS=$((10#$2 * 60 * 60))
      shift 2
      ;;
    --segment-days)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      SEGMENT_SECONDS=$((10#$2 * 24 * 60 * 60))
      shift 2
      ;;
    --segment-seconds)
      require_value "$1" "${2:-}"
      require_positive_int "$1" "$2"
      SEGMENT_SECONDS="$2"
      shift 2
      ;;
    --no-segment)
      SEGMENT_SECONDS=0
      shift
      ;;
    --backend)
      require_value "$1" "${2:-}"
      BACKEND="$2"
      shift 2
      ;;
    --keep-awake)
      KEEP_AWAKE=1
      shift
      ;;
    --list-devices)
      LIST_DEVICES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

command -v ffmpeg >/dev/null 2>&1 || fail "ffmpeg was not found. Install it with Homebrew: brew install ffmpeg"

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE '[[:space:]]libopus[[:space:]]'; then
  fail "this ffmpeg build does not include the libopus encoder"
fi

OS_NAME="$(uname -s)"

list_devices() {
  case "$OS_NAME" in
    Darwin)
      ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
        | sed \
          -e '/Error opening input/d' \
          -e '/Error opening input file/d' \
          -e '/Error opening input files/d' \
        || true
      ;;
    Linux)
      if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
        pactl list short sources
      elif command -v arecord >/dev/null 2>&1; then
        arecord -l
      else
        fail "no PulseAudio/PipeWire or ALSA device listing tool was found"
      fi
      ;;
    *)
      fail "device listing is not implemented for $OS_NAME"
      ;;
  esac
}

if [[ "$LIST_DEVICES" -eq 1 ]]; then
  list_devices
  exit 0
fi

INPUT_ARGS=()

case "$OS_NAME" in
  Darwin)
    DEVICE="${DEVICE:-0}"
    INPUT_ARGS=(-thread_queue_size 512 -f avfoundation -i ":${DEVICE}")
    ;;
  Linux)
    if [[ -z "$BACKEND" ]]; then
      if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
        BACKEND="pulse"
      else
        BACKEND="alsa"
      fi
    fi

    case "$BACKEND" in
      pulse)
        DEVICE="${DEVICE:-default}"
        INPUT_ARGS=(-thread_queue_size 512 -f pulse -i "$DEVICE")
        ;;
      alsa)
        DEVICE="${DEVICE:-default}"
        INPUT_ARGS=(-thread_queue_size 512 -f alsa -i "$DEVICE")
        ;;
      *)
        fail "unsupported Linux backend '$BACKEND' (expected pulse or alsa)"
        ;;
    esac
    ;;
  *)
    fail "unsupported OS '$OS_NAME'"
    ;;
esac

mkdir -p "$OUTPUT_DIR"

ENCODE_ARGS=(
  -map 0:a:0
  -vn
  -ac "$CHANNELS"
  -ar "$SAMPLE_RATE"
  -c:a libopus
  -application voip
  -b:a "$BITRATE"
  -vbr on
  -compression_level 10
  -frame_duration 60
)

if [[ "$KEEP_AWAKE" -eq 1 ]]; then
  if [[ "$OS_NAME" != "Darwin" ]]; then
    fail "--keep-awake is only implemented for macOS"
  fi

  command -v caffeinate >/dev/null 2>&1 || fail "caffeinate was not found"
fi

FFMPEG_PID=""
CAFFEINATE_PID=""
INTERRUPTED=0

stop_caffeinate() {
  if [[ -n "$CAFFEINATE_PID" ]] && kill -0 "$CAFFEINATE_PID" 2>/dev/null; then
    kill "$CAFFEINATE_PID" 2>/dev/null || true
    wait "$CAFFEINATE_PID" 2>/dev/null || true
  fi
}

next_output_file() {
  local base="$OUTPUT_DIR/mic_$(date +%Y%m%d_%H%M%S)"
  local output="$base.opus"
  local suffix=1

  while [[ -e "$output" ]]; do
    output="${base}_${suffix}.opus"
    suffix=$((suffix + 1))
  done

  printf '%s\n' "$output"
}

run_ffmpeg() {
  local output_file="$1"
  shift

  ffmpeg \
    -hide_banner \
    -nostdin \
    "${INPUT_ARGS[@]}" \
    "${ENCODE_ARGS[@]}" \
    "$@" \
    "$output_file" &

  FFMPEG_PID="$!"
  wait "$FFMPEG_PID"
  local status="$?"
  FFMPEG_PID=""
  return "$status"
}

force_stop() {
  echo "Force stopping recorder." >&2

  if [[ -n "$FFMPEG_PID" ]] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    kill -TERM "$FFMPEG_PID" 2>/dev/null || true
    sleep 2
    kill -KILL "$FFMPEG_PID" 2>/dev/null || true
  fi

  stop_caffeinate
  exit 130
}

graceful_stop() {
  local signal_name="$1"
  local exit_status=130

  case "$signal_name" in
    TERM) exit_status=143 ;;
    HUP) exit_status=129 ;;
    QUIT) exit_status=131 ;;
  esac

  if [[ "$INTERRUPTED" -eq 1 ]]; then
    force_stop
  fi

  INTERRUPTED=1
  trap force_stop INT TERM HUP QUIT

  echo
  echo "Stopping recorder gracefully. Waiting for ffmpeg to finalize the .opus file..."
  echo "Press Ctrl-C again to force-stop."

  set +e
  if [[ -n "$FFMPEG_PID" ]] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    if [[ "$signal_name" != "INT" ]]; then
      kill -TERM "$FFMPEG_PID" 2>/dev/null || true
    fi

    wait "$FFMPEG_PID" 2>/dev/null
  fi

  stop_caffeinate
  echo "Recording finalized."
  exit "$exit_status"
}

trap 'graceful_stop INT' INT
trap 'graceful_stop TERM' TERM
trap 'graceful_stop HUP' HUP
trap 'graceful_stop QUIT' QUIT

echo "Recording device: $DEVICE"
echo "Output dir: $OUTPUT_DIR"
echo "Encoding: Opus $BITRATE, ${SAMPLE_RATE} Hz, ${CHANNELS} channel(s)"
if [[ "$KEEP_AWAKE" -eq 1 ]]; then
  echo "Keep-awake: enabled"
fi
echo "Stop with Ctrl-C."

if [[ "$KEEP_AWAKE" -eq 1 ]]; then
  caffeinate -dimsu -w "$$" &
  CAFFEINATE_PID="$!"
fi

set +e

if [[ "$SEGMENT_SECONDS" -gt 0 ]]; then
  echo "File rotation: every ${SEGMENT_SECONDS}s"

  while :; do
    OUTPUT_FILE="$(next_output_file)"
    echo "Recording to: $OUTPUT_FILE"

    run_ffmpeg "$OUTPUT_FILE" -t "$SEGMENT_SECONDS"
    FFMPEG_STATUS="$?"

    if [[ "$FFMPEG_STATUS" -ne 0 ]]; then
      stop_caffeinate
      echo "Recorder stopped with ffmpeg status $FFMPEG_STATUS." >&2
      exit "$FFMPEG_STATUS"
    fi

    echo "Finalized: $OUTPUT_FILE"
  done
else
  OUTPUT_FILE="$(next_output_file)"
  echo "Recording to: $OUTPUT_FILE"

  run_ffmpeg "$OUTPUT_FILE"
  FFMPEG_STATUS="$?"
  stop_caffeinate

  if [[ "$INTERRUPTED" -eq 0 ]]; then
    echo "Recorder stopped."
  fi

  exit "$FFMPEG_STATUS"
fi
