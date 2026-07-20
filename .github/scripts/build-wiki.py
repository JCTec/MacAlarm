#!/usr/bin/env python3
"""Render docs/*.md (plus root CONTRIBUTING.md) into a GitHub wiki checkout.

Usage: build-wiki.py <wiki-dir> [repo-root]

- docs/<NAME>.md  -> <Wiki-Page>.md      (ARCHITECTURE.md -> Architecture.md)
- docs/WIKI_HOME.md -> Home.md
- CONTRIBUTING.md -> Contributing.md
- Relative doc-to-doc links (`](FOO.md)`, `](docs/FOO.md)`, with optional
  #anchor) are rewritten to wiki page links (`](Foo)`).
- Referenced images are copied into the wiki checkout and their paths flattened.
- Generates _Sidebar.md (grouped) and Home.md.

Direct wiki edits are overwritten; docs/ is the source of truth.
"""
from __future__ import annotations

import os
import re
import shutil
import sys

# Display titles for the sidebar (filename stem -> nice title). Anything not
# listed falls back to a title-cased derivation.
TITLE_OVERRIDES = {
    "SANDBOX_BEHAVIOR": "Sandbox Behavior",
    "SECURITY_MODEL": "Security Model",
    "CUSTOM_EVENTS": "Custom Events",
    "MACOS_BACKGROUND_PROCESS_GUIDE": "macOS Background Process Guide",
    "SWIFTUI_VIEWER": "SwiftUI Viewer",
    "LOGGING_PLAN": "Logging Plan",
    "PRODUCTION_READINESS": "Production Readiness",
    "RELEASE_CHECKLIST": "Release Checklist",
    "OPEN_SOURCE_ROADMAP": "Open-Source Roadmap",
    "TECHNICAL_PLAN": "Technical Plan",
}

# Sidebar grouping by page filename stem (post-mapping wiki page name).
SIDEBAR_GROUPS = [
    ("Start here", ["Home", "Architecture", "Security-Model", "Sandbox-Behavior"]),
    ("Using MacAlarm", ["Installer", "Uninstall", "Custom-Events", "Notifications", "Telegram"]),
    ("Building & releasing", ["Contributing", "Releasing", "Verification", "Release-Checklist"]),
]

IMAGE_RE = re.compile(r"(!\[[^\]]*\]\(|<img[^>]*src=\")([^)\"']+\.(?:png|jpg|jpeg|gif|svg))")
LINK_RE = re.compile(r"\]\((?:\./|docs/)?([A-Za-z0-9_./-]+\.md)(#[^)]*)?\)")


def wiki_page_name(md_filename: str) -> str:
    """ARCHITECTURE.md -> Architecture; SECURITY_MODEL.md -> Security-Model."""
    stem = md_filename[:-3] if md_filename.endswith(".md") else md_filename
    return "-".join(part.capitalize() for part in stem.split("_"))


def display_title(md_filename: str) -> str:
    stem = md_filename[:-3]
    if stem in TITLE_OVERRIDES:
        return TITLE_OVERRIDES[stem]
    return " ".join(part.capitalize() for part in stem.split("_"))


def rewrite_links(text: str, page_map: dict[str, str]) -> str:
    def repl(match: re.Match) -> str:
        target = os.path.basename(match.group(1))
        anchor = match.group(2) or ""
        page = page_map.get(target)
        if page is None:
            return match.group(0)
        return f"]({page}{anchor})"

    return LINK_RE.sub(repl, text)


def copy_images(text: str, source_dir: str, wiki_dir: str) -> str:
    def repl(match: re.Match) -> str:
        prefix, path = match.group(1), match.group(2)
        if path.startswith(("http://", "https://")):
            return match.group(0)
        candidate = os.path.normpath(os.path.join(source_dir, path))
        if not os.path.isfile(candidate):
            # Some doc images live at repo root (e.g. DesignAssets/...).
            candidate = os.path.normpath(os.path.join(REPO_ROOT, path))
        if not os.path.isfile(candidate):
            return match.group(0)
        flat = os.path.basename(candidate)
        dest = os.path.join(wiki_dir, flat)
        shutil.copyfile(candidate, dest)
        return f"{prefix}{flat}"

    return IMAGE_RE.sub(repl, text)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: build-wiki.py <wiki-dir> [repo-root]", file=sys.stderr)
        return 2

    wiki_dir = sys.argv[1]
    global REPO_ROOT
    REPO_ROOT = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
    docs_dir = os.path.join(REPO_ROOT, "docs")

    doc_files = sorted(f for f in os.listdir(docs_dir) if f.endswith(".md"))

    # Map every source .md basename to its wiki page name for link rewriting.
    page_map: dict[str, str] = {}
    for name in doc_files:
        page_map[name] = "Home" if name == "WIKI_HOME.md" else wiki_page_name(name)
    page_map["CONTRIBUTING.md"] = "Contributing"

    written_pages: list[str] = []

    def emit(source_path: str, source_name: str, page: str) -> None:
        with open(source_path, "r", encoding="utf-8") as handle:
            text = handle.read()
        text = rewrite_links(text, page_map)
        text = copy_images(text, os.path.dirname(source_path), wiki_dir)
        with open(os.path.join(wiki_dir, f"{page}.md"), "w", encoding="utf-8") as handle:
            handle.write(text)
        written_pages.append(page)
        print(f"  {source_name} -> {page}.md")

    for name in doc_files:
        page = page_map[name]
        emit(os.path.join(docs_dir, name), f"docs/{name}", page)

    contributing = os.path.join(REPO_ROOT, "CONTRIBUTING.md")
    if os.path.isfile(contributing):
        emit(contributing, "CONTRIBUTING.md", "Contributing")

    write_sidebar(wiki_dir, written_pages)
    print(f"Rendered {len(written_pages)} wiki pages into {wiki_dir}")
    return 0


def write_sidebar(wiki_dir: str, pages: list[str]) -> None:
    available = set(pages)
    used: set[str] = set()
    lines = ["### MacAlarm", ""]
    for group_title, group_pages in SIDEBAR_GROUPS:
        present = [p for p in group_pages if p in available]
        if not present:
            continue
        lines.append(f"**{group_title}**")
        lines.append("")
        for page in present:
            used.add(page)
            lines.append(f"- [{page_to_title(page)}]({page})")
        lines.append("")

    remaining = sorted(p for p in available if p not in used and p != "Home")
    if remaining:
        lines.append("**More**")
        lines.append("")
        for page in remaining:
            lines.append(f"- [{page_to_title(page)}]({page})")
        lines.append("")

    with open(os.path.join(wiki_dir, "_Sidebar.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")


def page_to_title(page: str) -> str:
    reverse = {wiki_page_name(f): display_title(f) for f in TITLE_OVERRIDES_SOURCE}
    if page in reverse:
        return reverse[page]
    return page.replace("-", " ")


# Filenames whose display titles are overridden, used to reverse-map page -> title.
TITLE_OVERRIDES_SOURCE = [f"{stem}.md" for stem in TITLE_OVERRIDES]


if __name__ == "__main__":
    raise SystemExit(main())
