#!/usr/bin/env python3
"""
Find CRITICAL unguarded setState() calls - those in async callbacks or after await.
These are the most dangerous as they can cause "setState called after dispose" errors.
"""

import re
from pathlib import Path
from collections import defaultdict

def is_in_async_context(lines, setState_line_idx):
    """Check if setState is after an await or in an async callback."""
    # Look back up to 10 lines
    start = max(0, setState_line_idx - 10)
    context = lines[start:setState_line_idx]
    context_text = ''.join(context)

    # Check for await in recent lines
    has_await = 'await ' in context_text

    # Check for async callback patterns
    has_async_callback = (
        'async {' in context_text or
        'async (' in context_text or
        '.then(' in context_text or
        'Future.' in context_text or
        'Timer(' in context_text or
        'Timer.periodic' in context_text
    )

    return has_await or has_async_callback

def analyze_file(filepath):
    """Analyze a single Dart file for CRITICAL unguarded setState calls."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return []

    critical = []

    for i, line in enumerate(lines):
        if 'setState(' in line:
            # Check for mounted guard
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
                # Check if in async context
                if is_in_async_context(lines, i):
                    # Get more context for display
                    display_start = max(0, i - 5)
                    display_context = ''.join(lines[display_start:i+1])

                    critical.append({
                        'line_num': i + 1,
                        'line': line.strip(),
                        'context': display_context
                    })

    return critical

def main():
    lib_dir = Path(r'c:\Users\Admin\arabica2026\lib')
    dart_files = list(lib_dir.rglob('*.dart'))

    # Group by module
    module_stats = defaultdict(lambda: {'files': set(), 'calls': 0, 'details': []})

    total_critical = 0

    for dart_file in dart_files:
        critical = analyze_file(dart_file)

        if critical:
            rel_path = dart_file.relative_to(lib_dir)
            parts = rel_path.parts

            # Determine module
            if len(parts) >= 2 and parts[0] == 'features':
                module = f"features/{parts[1]}"
            elif parts[0] in ['app', 'shared', 'core']:
                module = parts[0]
            else:
                module = 'other'

            module_stats[module]['files'].add(str(rel_path))
            module_stats[module]['calls'] += len(critical)
            module_stats[module]['details'].append({
                'file': str(rel_path),
                'issues': critical
            })

            total_critical += len(critical)

    print("=" * 100)
    print("CRITICAL UNGUARDED setState() CALLS (after await/async)")
    print("=" * 100)
    print()
    print("These setState calls are in async contexts and MUST have 'if (mounted)' guards.")
    print("They can cause 'setState called after dispose' runtime errors.")
    print()
    print("=" * 100)

    # Summary by module
    print("\nSUMMARY BY MODULE:")
    print("-" * 100)
    print(f"{'MODULE':<40} {'FILES':<10} {'CRITICAL CALLS':<15}")
    print("-" * 100)

    for module in sorted(module_stats.keys()):
        stats = module_stats[module]
        print(f"{module:<40} {len(stats['files']):<10} {stats['calls']:<15}")

    print("-" * 100)
    print(f"{'TOTAL':<40} {sum(len(s['files']) for s in module_stats.values()):<10} {total_critical:<15}")
    print("=" * 100)

    # Detailed list
    print("\n\nDETAILED LIST OF CRITICAL ISSUES:")
    print("=" * 100)

    issue_count = 0
    for module in sorted(module_stats.keys()):
        stats = module_stats[module]

        if stats['calls'] > 0:
            print(f"\n{'='*100}")
            print(f"MODULE: {module}")
            print(f"{'='*100}")

            for detail in stats['details']:
                print(f"\n  File: {detail['file']}")
                print(f"  Critical issues: {len(detail['issues'])}")
                print(f"  {'-'*96}")

                for issue in detail['issues']:
                    issue_count += 1
                    print(f"\n  [{issue_count}] Line {issue['line_num']}: {issue['line']}")
                    print(f"  Context (last 5 lines):")
                    for ctx_line in issue['context'].split('\n')[-6:-1]:
                        if ctx_line.strip():
                            print(f"    {ctx_line.rstrip()}")
                    print()

    print("\n" + "=" * 100)
    print(f"TOTAL CRITICAL ISSUES FOUND: {issue_count}")
    print("=" * 100)

if __name__ == '__main__':
    main()
