#!/usr/bin/env python3
"""
copy_repo_to_txt.py
===================
Exports an entire codebase into a single formatted text file.
Includes:
  1. Repository metadata & summary statistics
  2. Architecture / Directory tree diagram
  3. Formatted contents of all text files (with clear separators & metadata)

Usage:
    python3 scripts/copy_repo_to_txt.py
    python3 scripts/copy_repo_to_txt.py -o repo_dump.txt
    python3 scripts/copy_repo_to_txt.py --root /path/to/repo --output output.txt
"""

import argparse
import fnmatch
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Set, Tuple

# Default directory and file patterns to ignore
DEFAULT_IGNORED_DIRS: Set[str] = {
    ".git",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".venv",
    "venv",
    "env",
    "node_modules",
}

DEFAULT_IGNORED_FILES: Set[str] = {
    ".DS_Store",
    "Thumbs.db",
}

BINARY_EXTENSIONS: Set[str] = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".bmp", ".tiff",
    ".pdf", ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".rar",
    ".pyc", ".pyo", ".pyd", ".so", ".dylib", ".dll", ".exe", ".bin",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    ".mp3", ".mp4", ".wav", ".avi", ".mov", ".mkv",
}


def is_binary_file(file_path: Path) -> bool:
    """Heuristic check to determine if a file is binary."""
    if file_path.suffix.lower() in BINARY_EXTENSIONS:
        return True
    try:
        with open(file_path, "rb") as f:
            chunk = f.read(8192)
            if b"\0" in chunk:
                return True
    except (OSError, PermissionError):
        return True
    return False


def should_ignore(
    path: Path,
    root_path: Path,
    output_abs_path: Path,
    ignored_dirs: Set[str],
    ignored_files: Set[str],
    custom_patterns: List[str],
) -> bool:
    """Check if a file or directory should be excluded from processing."""
    try:
        abs_path = path.resolve()
        if abs_path == output_abs_path:
            return True
    except OSError:
        pass

    rel_path_str = str(path.relative_to(root_path)).replace("\\", "/")

    # Check exact directory name matches
    if path.is_dir() and path.name in ignored_dirs:
        return True

    # Check parent directory names
    for part in path.parts:
        if part in ignored_dirs:
            return True

    # Check exact file name matches
    if path.is_file() and path.name in ignored_files:
        return True

    # Check custom glob patterns against relative path or filename
    for pattern in custom_patterns:
        if fnmatch.fnmatch(rel_path_str, pattern) or fnmatch.fnmatch(path.name, pattern):
            return True

    return False


def build_tree(
    current_dir: Path,
    root_path: Path,
    output_abs_path: Path,
    ignored_dirs: Set[str],
    ignored_files: Set[str],
    custom_patterns: List[str],
    prefix: str = "",
) -> List[str]:
    """Recursively builds an ASCII architecture tree diagram."""
    lines: List[str] = []
    try:
        entries = sorted(
            [
                e for e in current_dir.iterdir()
                if not should_ignore(e, root_path, output_abs_path, ignored_dirs, ignored_files, custom_patterns)
            ],
            key=lambda e: (not e.is_dir(), e.name.lower())
        )
    except (PermissionError, OSError) as err:
        lines.append(f"{prefix}[Error reading directory: {err}]")
        return lines

    total = len(entries)
    for idx, entry in enumerate(entries):
        is_last = (idx == total - 1)
        connector = "└── " if is_last else "├── "
        display_name = f"{entry.name}/" if entry.is_dir() else entry.name
        lines.append(f"{prefix}{connector}{display_name}")

        if entry.is_dir():
            extension = "    " if is_last else "│   "
            sub_lines = build_tree(
                entry,
                root_path,
                output_abs_path,
                ignored_dirs,
                ignored_files,
                custom_patterns,
                prefix + extension,
            )
            lines.extend(sub_lines)

    return lines


def collect_files(
    root_path: Path,
    output_abs_path: Path,
    ignored_dirs: Set[str],
    ignored_files: Set[str],
    custom_patterns: List[str],
) -> List[Path]:
    """Collects all non-ignored files sorted by relative path."""
    collected: List[Path] = []
    for dirpath, dirnames, filenames in os.walk(root_path):
        current_dir = Path(dirpath)

        # Prune ignored directories in-place
        dirnames[:] = [
            d for d in dirnames
            if not should_ignore(current_dir / d, root_path, output_abs_path, ignored_dirs, ignored_files, custom_patterns)
        ]

        for fname in filenames:
            file_path = current_dir / fname
            if not should_ignore(file_path, root_path, output_abs_path, ignored_dirs, ignored_files, custom_patterns):
                collected.append(file_path)

    collected.sort(key=lambda p: str(p.relative_to(root_path)).lower())
    return collected


def format_size(size_bytes: int) -> str:
    """Format bytes into human-readable string."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size_bytes < 1024.0 or unit == "GB":
            return f"{size_bytes:.1f} {unit}" if unit != "B" else f"{size_bytes} B"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} GB"


def export_repository(
    root_dir: str = ".",
    output_file: str = "repo_bundle.txt",
    extra_excludes: List[str] = None,
    max_file_size_kb: int = 1024,
) -> None:
    """Main function to export the repository into a single text file."""
    root_path = Path(root_dir).resolve()
    output_path = Path(output_file).resolve()

    if not root_path.exists() or not root_path.is_dir():
        print(f"Error: Root directory '{root_dir}' does not exist or is not a directory.", file=sys.stderr)
        sys.exit(1)

    ignored_dirs = set(DEFAULT_IGNORED_DIRS)
    ignored_files = set(DEFAULT_IGNORED_FILES)
    custom_patterns = extra_excludes or []

    print(f"🔍 Analyzing repository at: {root_path}")
    print(f"📁 Output target: {output_path}")

    # Collect files
    files = collect_files(root_path, output_path, ignored_dirs, ignored_files, custom_patterns)

    # Count directories
    dirs_count = 0
    for dirpath, dirnames, _ in os.walk(root_path):
        current_dir = Path(dirpath)
        dirnames[:] = [
            d for d in dirnames
            if not should_ignore(current_dir / d, root_path, output_path, ignored_dirs, ignored_files, custom_patterns)
        ]
        dirs_count += len(dirnames)

    total_bytes = sum(f.stat().st_size for f in files if f.exists())

    print(f"📊 Discovered {len(files)} files across {dirs_count} directories ({format_size(total_bytes)}).")
    print("🌲 Generating architecture tree...")

    # Build architecture tree
    tree_lines = [f"{root_path.name}/"]
    tree_lines.extend(build_tree(root_path, root_path, output_path, ignored_dirs, ignored_files, custom_patterns))
    tree_diagram = "\n".join(tree_lines)

    # Write to output file
    print("✍️  Writing bundle to file...")
    separator_major = "=" * 80
    separator_minor = "-" * 80

    with open(output_path, "w", encoding="utf-8") as out:
        # Header Metadata
        out.write(f"{separator_major}\n")
        out.write(f"REPOSITORY EXPORT BUNDLE\n")
        out.write(f"{separator_major}\n")
        out.write(f"Repository Name : {root_path.name}\n")
        out.write(f"Root Directory  : {root_path}\n")
        out.write(f"Generated On    : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        out.write(f"Total Files     : {len(files)}\n")
        out.write(f"Total Folders   : {dirs_count}\n")
        out.write(f"Total Size      : {format_size(total_bytes)}\n")
        out.write(f"{separator_major}\n\n")

        # Section 1: Architecture Tree Diagram
        out.write(f"{separator_major}\n")
        out.write(f"SECTION 1: ARCHITECTURE TREE DIAGRAM\n")
        out.write(f"{separator_major}\n\n")
        out.write(f"{tree_diagram}\n\n")

        # Section 2: File Contents
        out.write(f"{separator_major}\n")
        out.write(f"SECTION 2: FILE CONTENTS\n")
        out.write(f"{separator_major}\n\n")

        for idx, file_path in enumerate(files, 1):
            rel_path = file_path.relative_to(root_path).as_posix()
            file_size = file_path.stat().st_size
            formatted_size = format_size(file_size)

            out.write(f"{separator_major}\n")
            out.write(f"[{idx}/{len(files)}] FILE: {rel_path}\n")
            out.write(f"SIZE: {formatted_size} ({file_size} bytes)\n")

            # Check max file size
            if file_size > max_file_size_kb * 1024:
                out.write(f"STATUS: Omitted (exceeds limit of {max_file_size_kb} KB)\n")
                out.write(f"{separator_major}\n\n")
                continue

            # Check binary
            if is_binary_file(file_path):
                out.write(f"STATUS: Binary file (raw content omitted)\n")
                out.write(f"{separator_major}\n\n")
                continue

            # Text content
            out.write(f"{separator_major}\n")
            try:
                with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                    out.write(content)
                    if not content.endswith("\n"):
                        out.write("\n")
            except Exception as e:
                out.write(f"[Error reading file: {e}]\n")
            out.write("\n")

    output_size = output_path.stat().st_size
    print(f"✅ Repository successfully exported!")
    print(f"📄 Output file: {output_path} ({format_size(output_size)})")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Copy entire repository into a single text file with architecture tree diagram and file contents."
    )
    parser.add_argument(
        "-r", "--root",
        default=".",
        help="Path to repository root directory (default: current directory)."
    )
    parser.add_argument(
        "-o", "--output",
        default="repo_bundle.txt",
        help="Path for destination text file (default: repo_bundle.txt)."
    )
    parser.add_argument(
        "-e", "--exclude",
        action="append",
        default=[],
        help="Additional glob pattern or directory to exclude (can be specified multiple times)."
    )
    parser.add_argument(
        "--max-size-kb",
        type=int,
        default=1024,
        help="Maximum size in KB for individual files before skipping content (default: 1024 KB / 1 MB)."
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    export_repository(
        root_dir=args.root,
        output_file=args.output,
        extra_excludes=args.exclude,
        max_file_size_kb=args.max_size_kb,
    )
