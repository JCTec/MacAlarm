#!/usr/bin/env python3
"""Detect coarse audio events in recorded Opus files with YAMNet.

This is a local, first-pass classifier. It does not upload audio anywhere.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd
import tensorflow_hub as hub


DEFAULT_KEYWORDS = [
    "speech",
    "conversation",
    "narration",
    "snoring",
    "breathing",
    "cough",
    "sneeze",
    "door",
    "doorbell",
    "knock",
    "tap",
    "faucet",
    "water",
    "sink",
    "toilet",
    "shower",
    "footstep",
    "walk",
    "typing",
    "keyboard",
    "mouse",
    "television",
    "radio",
    "music",
    "alarm",
    "siren",
    "glass",
    "dishes",
    "cutlery",
    "microwave",
    "vacuum",
    "appliance",
    "motor",
]


FILENAME_RE = re.compile(r"mic_(\d{8})_(\d{6})")


def run_text(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True).strip()


def probe_duration(path: Path) -> float:
    raw = run_text(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
    )
    return float(raw)


def decode_chunk(path: Path, start: float, duration: float, sample_rate: int) -> np.ndarray:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{start:.3f}",
        "-t",
        f"{duration:.3f}",
        "-i",
        str(path),
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "f32le",
        "pipe:1",
    ]
    raw = subprocess.check_output(cmd)
    return np.frombuffer(raw, dtype=np.float32)


def recording_start(path: Path, timezone_name: str) -> datetime:
    match = FILENAME_RE.search(path.name)
    zone = ZoneInfo(timezone_name)

    if match:
        stamp = "".join(match.groups())
        return datetime.strptime(stamp, "%Y%m%d%H%M%S").replace(tzinfo=zone)

    return datetime.fromtimestamp(path.stat().st_mtime, tz=zone)


def load_yamnet():
    model = hub.load("https://tfhub.dev/google/yamnet/1")
    class_map_path = model.class_map_path().numpy().decode("utf-8")
    class_names = pd.read_csv(class_map_path)["display_name"].tolist()
    return model, class_names


def should_keep(label: str, keywords: list[str]) -> bool:
    lower = label.lower()
    return any(keyword in lower for keyword in keywords)


def iter_files(input_dir: Path, recent: int | None, explicit_files: list[Path]) -> list[Path]:
    if explicit_files:
        return explicit_files

    files = sorted(input_dir.glob("*.opus"), key=lambda p: p.stat().st_mtime)
    if recent is not None and recent > 0:
        return files[-recent:]
    return files


def analyze_file(
    *,
    path: Path,
    model,
    class_names: list[str],
    output_handle,
    args: argparse.Namespace,
    keywords: list[str],
    summary: Counter,
) -> None:
    duration = probe_duration(path)
    start_time = recording_start(path, args.timezone)
    chunk_count = int(math.ceil(duration / args.chunk_seconds))

    for chunk_index in range(chunk_count):
        if args.max_chunks and summary["chunks_seen"] >= args.max_chunks:
            return

        chunk_start = chunk_index * args.chunk_seconds
        if chunk_start >= duration:
            break

        chunk_duration = min(args.chunk_seconds, duration - chunk_start)
        waveform = decode_chunk(path, chunk_start, chunk_duration, args.sample_rate)
        if waveform.size == 0:
            continue

        scores, _, _ = model(waveform)
        max_scores = np.max(scores.numpy(), axis=0)
        ranked = np.argsort(max_scores)[::-1]

        kept = 0
        for class_index in ranked:
            label = class_names[int(class_index)]
            score = float(max_scores[int(class_index)])

            if score < args.threshold:
                break

            if args.targets_only and not should_keep(label, keywords):
                continue

            event_start = start_time + timedelta(seconds=chunk_start)
            event_end = start_time + timedelta(seconds=chunk_start + chunk_duration)
            row = {
                "start": event_start.isoformat(),
                "end": event_end.isoformat(),
                "chunk_start_sec": round(chunk_start, 3),
                "chunk_end_sec": round(chunk_start + chunk_duration, 3),
                "label": label,
                "score": round(score, 4),
                "file": str(path),
            }
            output_handle.write(json.dumps(row, sort_keys=True) + "\n")
            output_handle.flush()

            summary[f"label:{label}"] += 1
            summary["events"] += 1
            kept += 1

            if kept >= args.top_k:
                break

        summary["chunks_seen"] += 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect coarse sound events in Opus recordings using YAMNet."
    )
    parser.add_argument("--input-dir", type=Path, default=Path.home() / "AudioRecordings")
    parser.add_argument(
        "--file",
        action="append",
        type=Path,
        default=[],
        help="Specific .opus file to analyze. Can be passed more than once.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("audio-events.jsonl"),
        help="JSONL output path.",
    )
    parser.add_argument("--recent", type=int, default=1, help="Analyze the N most recent files.")
    parser.add_argument("--all", action="store_true", help="Analyze all .opus files.")
    parser.add_argument("--chunk-seconds", type=float, default=10.0)
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--threshold", type=float, default=0.18)
    parser.add_argument("--top-k", type=int, default=4)
    parser.add_argument(
        "--max-chunks",
        type=int,
        default=60,
        help="Safety limit across files. Use 0 for no limit.",
    )
    parser.add_argument(
        "--keywords",
        default=",".join(DEFAULT_KEYWORDS),
        help="Comma-separated label substrings to keep when --targets-only is enabled.",
    )
    parser.add_argument(
        "--targets-only",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Keep only labels matching the home/sleep keyword list.",
    )
    parser.add_argument("--timezone", default="America/Merida")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.max_chunks = max(args.max_chunks, 0)
    if args.all:
        args.recent = None

    keywords = [item.strip().lower() for item in args.keywords.split(",") if item.strip()]
    files = iter_files(args.input_dir, args.recent, args.file)

    if not files:
        print(f"No .opus files found in {args.input_dir}")
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(f"Loading YAMNet model...")
    model, class_names = load_yamnet()
    print(f"Analyzing {len(files)} file(s); writing {args.output}")

    summary: Counter = Counter()
    with args.output.open("w", encoding="utf-8") as output_handle:
        for path in files:
            print(f"File: {path.name}")
            analyze_file(
                path=path,
                model=model,
                class_names=class_names,
                output_handle=output_handle,
                args=args,
                keywords=keywords,
                summary=summary,
            )
            if args.max_chunks and summary["chunks_seen"] >= args.max_chunks:
                break

    print(f"Chunks analyzed: {summary['chunks_seen']}")
    print(f"Events written: {summary['events']}")
    for label, count in summary.most_common(15):
        if label.startswith("label:"):
            print(f"{label.removeprefix('label:')}: {count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
