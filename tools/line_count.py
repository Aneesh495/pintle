#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tools/line_count.py
Description: Codebase line counting, comment-to-code ratio, and metrics auditor.
             Scans Bluespec SystemVerilog modules, C++ simulation harness,
             Python test suites, and architectural technical documentation.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import os
import sys
from typing import Dict, List, Tuple

LANGUAGE_SPECS = {
    "Bluespec SystemVerilog": {
        "extensions": [".bsv"],
        "line_comment": ["//"],
        "block_comment": [("/*", "*/")],
    },
    "C++ / Headers": {
        "extensions": [".cpp", ".hpp", ".c", ".h"],
        "line_comment": ["//"],
        "block_comment": [("/*", "*/")],
    },
    "Python": {
        "extensions": [".py"],
        "line_comment": ["#"],
        "block_comment": [('"""', '"""'), ("'''", "'''")],
    },
    "Documentation": {
        "extensions": [".md"],
        "line_comment": [],
        "block_comment": [("<!--", "-->")],
    },
    "Build & Config": {
        "extensions": ["Makefile", ".gitignore", ".gitattributes", "LICENSE", ".editorconfig", ".yml", ".sh"],
        "line_comment": ["#"],
        "block_comment": [],
    },
}

EXCLUDED_DIRS = {
    ".git",
    "build",
    "bin",
    "sim_build",
    "obj_dir",
    "__pycache__",
    ".zig-cache",
}

def analyze_file(filepath: str, spec: dict) -> Tuple[int, int, int]:
    code_lines = 0
    comment_lines = 0
    blank_lines = 0
    in_block = False
    block_end = ""

    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if not stripped:
                    blank_lines += 1
                    continue

                if in_block:
                    comment_lines += 1
                    if block_end in stripped:
                        in_block = False
                    continue

                # Check block comment start
                started_block = False
                for start_tok, end_tok in spec.get("block_comment", []):
                    if stripped.startswith(start_tok):
                        comment_lines += 1
                        if end_tok not in stripped[len(start_tok):]:
                            in_block = True
                            block_end = end_tok
                        started_block = True
                        break
                if started_block:
                    continue

                # Check line comment
                is_line_comment = False
                for tok in spec.get("line_comment", []):
                    if stripped.startswith(tok):
                        comment_lines += 1
                        is_line_comment = True
                        break
                if is_line_comment:
                    continue

                code_lines += 1

    except Exception as e:
        print(f"Warning: Failed to read {filepath}: {e}", file=sys.stderr)

    return code_lines, comment_lines, blank_lines

def scan_project(root_dir: str) -> Dict[str, Dict[str, int]]:
    results = {
        lang: {"files": 0, "code": 0, "comments": 0, "blanks": 0, "total": 0}
        for lang in LANGUAGE_SPECS
    }

    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            matched_lang = None

            for lang, spec in LANGUAGE_SPECS.items():
                if ext in spec["extensions"] or filename in spec["extensions"]:
                    matched_lang = lang
                    break

            if matched_lang:
                full_path = os.path.join(dirpath, filename)
                spec = LANGUAGE_SPECS[matched_lang]
                c, m, b = analyze_file(full_path, spec)
                results[matched_lang]["files"] += 1
                results[matched_lang]["code"] += c
                results[matched_lang]["comments"] += m
                results[matched_lang]["blanks"] += b
                results[matched_lang]["total"] += (c + m + b)

    return results

def print_report(results: Dict[str, Dict[str, int]]):
    print("=" * 80)
    print("PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller")
    print("Codebase Metrics and Line Count Auditor")
    print("=" * 80)
    print(f"{'Category':<26} {'Files':>6} {'Code':>9} {'Comments':>9} {'Blank':>7} {'Total':>9} {'Cmt/Code':>9}")
    print("-" * 80)

    total_files = 0
    total_code = 0
    total_comments = 0
    total_blanks = 0
    total_lines = 0

    for lang, metrics in results.items():
        ratio_str = f"{(metrics['comments'] / metrics['code']):.2f}" if metrics['code'] > 0 else "0.00"
        print(f"{lang:<26} {metrics['files']:>6} {metrics['code']:>9} {metrics['comments']:>9} {metrics['blanks']:>7} {metrics['total']:>9} {ratio_str:>9}")
        total_files += metrics["files"]
        total_code += metrics["code"]
        total_comments += metrics["comments"]
        total_blanks += metrics["blanks"]
        total_lines += metrics["total"]

    print("-" * 80)
    overall_ratio = f"{(total_comments / total_code):.2f}" if total_code > 0 else "0.00"
    print(f"{'TOTAL':<26} {total_files:>6} {total_code:>9} {total_comments:>9} {total_blanks:>7} {total_lines:>9} {overall_ratio:>9}")
    print("=" * 80)

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    results = scan_project(root)
    print_report(results)

if __name__ == "__main__":
    main()
