#!/usr/bin/env python3
"""
catall.py — print a directory tree and emit whitelisted file contents in Markdown or XML,
with robust exclude rules.

Examples:
  # Exclude by directory names (at any depth)
  python catall.py . -d SolverSite,raw_text,acquisition --tree

  # Mix: exclude dirs + specific filenames + extensions + subtrees
  python catall.py . -d env,venv -x "private.css,html,docs/generated/*" --format xml
"""

import os
import sys
import argparse
import xml.etree.ElementTree as ET
from xml.dom import minidom
import subprocess
from typing import Set, List, Optional
import pyperclip
# Whitelist for code file extensions (lowercase, no leading dot)
WHITELIST_EXTS = {
    'scala', 'bta', 'proxy', 'dockerfile', 'flag', 'md', 'py', 'sage', 'js',
    'html', 'css', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'swift',
    'kt', 'ts', 'php', 'rb', 'conf', 'txt', 'sh', 'bash', 'sql', 'yaml', 'yml',
    'json', 'xml', 'crontab'
}

# Always-skip directories by name (on top of user-provided -d)
BLACKLIST_DIRS = {'__pycache__/', 'node_modules/', '.git', '.vscode', '.idea', 'migrations', '.env/', '.venv/', '.claude/'}


def get_file_extension(filename: str) -> str:
    """
    Return lowercase extension WITHOUT dot.
    Special-case: files like 'Dockerfile' -> treat entire name as extension tag if whitelisted.
    """
    base = os.path.basename(filename)
    _, ext = os.path.splitext(base)
    if ext:
        return ext[1:].lower()
    low = base.lower()
    return low if low in WHITELIST_EXTS else ""


class Exclusions:
    """
    Parsed exclusion rules:
      - dirnames: {'env', 'acquisition', ...} (match any path component)  <-- from -d/--exclude-dirs
      - dirpaths: ['/abs/path/to/build', '/abs/dir/docs/generated', ...]  (subtrees from -x tokens like foo/* or paths)
      - filenames: {'private.css', 'secrets.json', ...} (case-insensitive exact basename from -x)
      - exts: {'html', 'css', ...} (from -x)
    """
    def __init__(self, base_dir: str) -> None:
        self.base_dir = os.path.abspath(base_dir)
        self.dirnames: Set[str] = set()
        self.dirpaths: List[str] = []
        self.filenames: Set[str] = set()
        self.exts: Set[str] = set()

    # ---- population helpers ----
    def add_dirnames(self, csv: Optional[str]) -> None:
        """Populate directory-name exclusions from -d / --exclude-dirs."""
        if not csv:
            return
        for tok in (t.strip() for t in csv.split(",") if t.strip()):
            self.dirnames.add(tok)

    def add_generic_token(self, token: str) -> None:
        """
        Populate exclusions from -x / --exclude:
          - 'name/*' => subtree (dirpath) relative to base dir
          - 'path/like/this' (no /*) => subtree (dirpath) relative to base dir
          - 'private.css' => exact filename (basename)
          - 'html' => extension
        """
        t = token.strip()
        if not t:
            return

        # subtree like "build/*"
        if t.endswith("/*"):
            rel = t[:-2].strip().strip(os.sep)
            if rel:
                self.dirpaths.append(os.path.normpath(os.path.join(self.base_dir, rel)))
            return

        # contains a path separator -> treat as subtree relative to base
        if os.sep in t:
            self.dirpaths.append(os.path.normpath(os.path.join(self.base_dir, t)))
            return

        # dotted token with no path sep → exact filename
        if "." in t:
            self.filenames.add(t.lower())
            return

        # otherwise treat as an extension token (optional behavior)
        self.exts.add(t.lower())

    def add_generic_csv(self, csv: Optional[str]) -> None:
        if not csv:
            return
        for tok in (t.strip() for t in csv.split(",") if t.strip()):
            self.add_generic_token(tok)

    # ---- checks ----
    def exclude_dir(self, path: str) -> bool:
        apath = os.path.abspath(path)
        name = os.path.basename(apath)

        # Always-blacklist first
        if name in BLACKLIST_DIRS:
            return True

        # directory name rule: any path component matches -d names
        parts = apath.split(os.sep)
        if any(p in self.dirnames for p in parts if p):
            return True

        # subtree rule: path under any excluded dirpath
        for dp in self.dirpaths:
            if apath == dp or apath.startswith(dp + os.sep):
                return True

        return False

    def exclude_file(self, path: str) -> bool:
        apath = os.path.abspath(path)

        # subtree rule
        for dp in self.dirpaths:
            if apath == dp or apath.startswith(dp + os.sep):
                return True

        # parent dirnames rule
        parts = apath.split(os.sep)
        if any(p in self.dirnames for p in parts[:-1]):
            return True

        # filename rule
        if os.path.basename(apath).lower() in self.filenames:
            return True

        # extension rule
        ext = get_file_extension(apath)
        if ext and ext in self.exts:
            return True

        return False


def print_directory_structure(directory: str, prefix: str = "", excl: Optional[Exclusions] = None) -> None:
    items = sorted(os.listdir(directory))

    # compute filtered list once so last-branch selection is correct
    def visible(entry: str) -> bool:
        p = os.path.join(directory, entry)
        if os.path.isdir(p):
            if excl and excl.exclude_dir(p):
                return False
        return True

    vis_items = [it for it in items if visible(it)]
    for idx, item in enumerate(vis_items):
        path = os.path.join(directory, item)
        is_dir = os.path.isdir(path)
        is_last = idx == (len(vis_items) - 1)

        branch = "└── " if is_last else "├── "
        print(f"{prefix}{branch}{item}")

        if is_dir:
            next_prefix = prefix + ("    " if is_last else "│   ")
            print_directory_structure(path, next_prefix, excl)


def format_markdown(base_dir: str, excl: Optional[Exclusions] = None) -> str:
    out: List[str] = []
    for root, dirs, files in os.walk(base_dir):
        # prune dirs
        abs_dir = os.path.abspath(root)
        pruned = []
        for d in dirs:
            abs_d = os.path.abspath(os.path.join(abs_dir, d))
            if excl and excl.exclude_dir(abs_d):
                continue
            pruned.append(d)
        dirs[:] = pruned

        # files
        for fname in files:
            abs_fp = os.path.abspath(os.path.join(root, fname))
            if excl and excl.exclude_file(abs_fp):
                continue

            ext = get_file_extension(fname)
            if ext not in WHITELIST_EXTS:
                continue

            rel_path = os.path.relpath(abs_fp, base_dir)
            out.append(f"\n## {rel_path}\n")
            out.append(f"```{ext or ''}".rstrip())
            try:
                with open(abs_fp, "r", encoding="utf-8") as f:
                    out.append(f.read())
            except Exception as e:
                out.append(f"Error reading file {rel_path}: {e}")
            out.append("```")
    return "\n".join(out)


def format_xml(base_dir: str, excl: Optional[Exclusions] = None) -> str:
    root_elem = ET.Element("directory")
    for root, dirs, files in os.walk(base_dir):
        # prune dirs
        abs_dir = os.path.abspath(root)
        pruned = []
        for d in dirs:
            abs_d = os.path.abspath(os.path.join(abs_dir, d))
            if excl and excl.exclude_dir(abs_d):
                continue
            pruned.append(d)
        dirs[:] = pruned

        for fname in files:
            abs_fp = os.path.abspath(os.path.join(root, fname))
            if excl and excl.exclude_file(abs_fp):
                continue

            ext = get_file_extension(fname)
            if ext not in WHITELIST_EXTS:
                continue

            rel_path = os.path.relpath(abs_fp, base_dir)
            file_elem = ET.SubElement(root_elem, "file")
            path_elem = ET.SubElement(file_elem, "path")
            path_elem.text = rel_path
            content_elem = ET.SubElement(file_elem, "content")
            try:
                with open(abs_fp, "r", encoding="utf-8") as f:
                    content_elem.text = f.read()
            except Exception as e:
                content_elem.text = f"Error reading file {rel_path}: {e}"
            lang_elem = ET.SubElement(file_elem, "language")
            lang_elem.text = ext

    xml_str = ET.tostring(root_elem, encoding="unicode")
    parsed = minidom.parseString(xml_str)
    return parsed.toprettyxml(indent="  ")


def format_directory_content(base_dir: str, output_format: str, excl: Optional[Exclusions] = None) -> str:
    if output_format == "markdown":
        return format_markdown(base_dir, excl)
    elif output_format == "xml":
        return format_xml(base_dir, excl)
    else:
        raise ValueError("Invalid output format. Choose 'markdown' or 'xml'.")


def main():
    p = argparse.ArgumentParser(description="Emit directory contents in Markdown or XML with robust excludes.")
    p.add_argument("directory", help="Path to the directory")
    p.add_argument("--tree", action="store_true", help="Print directory tree before file contents")
    p.add_argument("--cl", action="store_true", help="Copy output to clipboard with xclip")
    p.add_argument("--format", choices=["markdown", "xml"], default="markdown", help="Output format")
    p.add_argument(
        "-x", "--exclude",
        help=("Comma-separated list of rules: "
              "extensions (e.g., html,css), exact filenames (e.g., private.css), "
              "or relative subtrees with /* or path (e.g., build/*, docs/generated).")
    )
    p.add_argument(
        "-d", "--exclude-dirs",
        help="Comma-separated directory NAMES to exclude anywhere (e.g., env,venv,acquisition)."
    )
    p.add_argument(
        "-a", "--only",
        help="catall only certain file types, such as '*.py', flag takes precedence over all other cmds first."

    )
    args = p.parse_args()

    base_dir = os.path.abspath(args.directory)
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    # Build exclusions
    excl = Exclusions(base_dir)
    excl.add_dirnames(args.exclude_dirs)
    excl.add_generic_csv(args.exclude)

    # Optional tree
    if args.tree:
        print("# Directory Structure")
        print_directory_structure(base_dir, excl=excl)
        print()

    # Content
    print(f"# File Contents ({args.format.capitalize()} Format)")
    formatted = format_directory_content(base_dir, args.format, excl=excl)
    print(formatted)

    # Clipboard
    if args.cl:
        try:
            subprocess.run(['xclip', '-selection', 'clipboard'], input=formatted, text=True, check=True)
            print("\nContent copied to clipboard!")
        except Exception as e:
            print(
                f"\nUnable to copy to clipboard: {e}\n"
                "Ensure 'xclip' is installed and available in PATH.",
                file=sys.stderr,
            )


if __name__ == "__main__":
    main()

