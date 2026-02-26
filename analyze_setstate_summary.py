#!/usr/bin/env python3
"""
Generate summary statistics for unguarded setState() calls grouped by directory.
"""

import re
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
        if 'setState(' in line:
            context_start = max(0, i - 2)
            context_lines = lines[context_start:i]
            context_text = ''.join(context_lines)

            has_mounted_guard = (
                'if (mounted)' in context_text or
                'if (!mounted)' in context_text or
                'if(!mounted)' in context_text or
                'if (mounted &&' in context_text or
                'if (!mounted ||' in context_text
            )

            if not has_mounted_guard:
                unguarded.append(i + 1)

    return unguarded

def main():
    lib_dir = Path(r'c:\Users\Admin\arabica2026\lib')
    dart_files = list(lib_dir.rglob('*.dart'))

    # Group by feature/module
    module_stats = defaultdict(lambda: {'files': 0, 'calls': 0, 'file_list': []})

    for dart_file in dart_files:
        unguarded = analyze_file(dart_file)

        if unguarded:
            rel_path = dart_file.relative_to(lib_dir)
            parts = rel_path.parts

            # Determine module
            if len(parts) >= 2 and parts[0] == 'features':
                module = f"features/{parts[1]}"
            elif parts[0] in ['app', 'shared', 'core']:
                module = parts[0]
            else:
                module = 'other'

            module_stats[module]['files'] += 1
            module_stats[module]['calls'] += len(unguarded)
            module_stats[module]['file_list'].append((str(rel_path), len(unguarded)))

    # Print summary by module
    print("=" * 100)
    print("UNGUARDED setState() CALLS - SUMMARY BY MODULE")
    print("=" * 100)
    print(f"\n{'MODULE':<40} {'FILES':<10} {'CALLS':<10} {'AVG/FILE':<10}")
    print("-" * 100)

    total_files = 0
    total_calls = 0

    for module in sorted(module_stats.keys()):
        stats = module_stats[module]
        avg = stats['calls'] / stats['files']
        print(f"{module:<40} {stats['files']:<10} {stats['calls']:<10} {avg:<10.1f}")
        total_files += stats['files']
        total_calls += stats['calls']

    print("-" * 100)
    print(f"{'TOTAL':<40} {total_files:<10} {total_calls:<10} {total_calls/total_files:<10.1f}")
    print("=" * 100)

    # Top 20 worst offenders
    print("\n" + "=" * 100)
    print("TOP 20 FILES WITH MOST UNGUARDED setState CALLS")
    print("=" * 100)

    all_files = []
    for module, stats in module_stats.items():
        for filepath, count in stats['file_list']:
            all_files.append((filepath, count))

    all_files.sort(key=lambda x: x[1], reverse=True)

    print(f"\n{'FILE':<70} {'CALLS':<10}")
    print("-" * 100)
    for filepath, count in all_files[:20]:
        print(f"{filepath:<70} {count:<10}")

    print("=" * 100)

    # Modules sorted by severity (calls per file)
    print("\n" + "=" * 100)
    print("MODULES BY SEVERITY (avg unguarded setState per file)")
    print("=" * 100)

    severity_list = []
    for module, stats in module_stats.items():
        avg = stats['calls'] / stats['files']
        severity_list.append((module, avg, stats['files'], stats['calls']))

    severity_list.sort(key=lambda x: x[1], reverse=True)

    print(f"\n{'MODULE':<40} {'AVG/FILE':<12} {'FILES':<10} {'TOTAL CALLS':<10}")
    print("-" * 100)
    for module, avg, files, calls in severity_list:
        print(f"{module:<40} {avg:<12.1f} {files:<10} {calls:<10}")

    print("=" * 100)

if __name__ == '__main__':
    main()
