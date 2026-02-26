#!/usr/bin/env python3
"""
Analyze Dart files for unguarded setState() calls.
A setState is considered unguarded if it doesn't have:
- if (mounted) within 2 lines before it
- if (!mounted) return; within 2 lines before it
"""

import re
import os
from pathlib import Path
from collections import defaultdict

def analyze_file(filepath):
    """Analyze a single Dart file for unguarded setState calls."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return []

    unguarded = []

    for i, line in enumerate(lines):
        # Check if this line contains setState(
        if 'setState(' in line:
            # Look at the 2 previous lines for guards
            context_start = max(0, i - 2)
            context_lines = lines[context_start:i]
            context_text = ''.join(context_lines)

            # Check for mounted guards
            has_mounted_guard = (
                'if (mounted)' in context_text or
                'if (!mounted)' in context_text or
                'if(!mounted)' in context_text or
                'if (mounted &&' in context_text or
                'if (!mounted ||' in context_text
            )

            if not has_mounted_guard:
                # This is an unguarded setState
                unguarded.append({
                    'line_num': i + 1,  # 1-indexed
                    'line': line.strip(),
                    'context': context_text
                })

    return unguarded

def main():
    lib_dir = Path(r'c:\Users\Admin\arabica2026\lib')

    # Find all .dart files
    dart_files = list(lib_dir.rglob('*.dart'))

    # Group results by directory
    results_by_dir = defaultdict(list)
    total_unguarded = 0
    total_files_with_issues = 0

    for dart_file in dart_files:
        unguarded = analyze_file(dart_file)

        if unguarded:
            rel_path = dart_file.relative_to(lib_dir.parent)
            dir_name = str(rel_path.parent)

            results_by_dir[dir_name].append({
                'file': str(rel_path),
                'unguarded_calls': unguarded
            })

            total_unguarded += len(unguarded)
            total_files_with_issues += 1

    # Print results organized by directory
    print("=" * 80)
    print("UNGUARDED setState() CALLS REPORT")
    print("=" * 80)
    print()

    # Sort directories for consistent output
    for dir_name in sorted(results_by_dir.keys()):
        files = results_by_dir[dir_name]

        print(f"\n{'=' * 80}")
        print(f"Directory: {dir_name}")
        print(f"{'=' * 80}")

        for file_info in sorted(files, key=lambda x: x['file']):
            print(f"\n  File: {file_info['file']}")
            print(f"  Unguarded setState calls: {len(file_info['unguarded_calls'])}")
            print(f"  {'-' * 76}")

            for call in file_info['unguarded_calls']:
                print(f"    Line {call['line_num']}: {call['line']}")

            print()

    # Print summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total files with unguarded setState: {total_files_with_issues}")
    print(f"Total unguarded setState calls: {total_unguarded}")
    print(f"Total .dart files scanned: {len(dart_files)}")
    print("=" * 80)

if __name__ == '__main__':
    main()
