"""
Find truly unguarded setState calls.
A setState is guarded if within 5 lines above there's ANY occurrence of
'mounted' in an if/while condition context.
"""
import os
import sys
import re

# Pattern: line contains a conditional with 'mounted'
# e.g.: if (mounted), if (!mounted), if (mounted &&), if (x != null && mounted)
GUARD_RE = re.compile(r'\bmounted\b')


def line_has_guard(line):
    """Check if a line is an if/guard containing 'mounted'."""
    stripped = line.strip()
    if GUARD_RE.search(stripped):
        # Make sure it's a conditional or guard, not a comment or string
        if stripped.startswith('//') or stripped.startswith('*'):
            return False
        return True
    return False


def is_sync_callback(line):
    """Detect simple lambda callbacks that don't need guards."""
    # Pattern: onXxx: (x) => setState(...)  or  onXxx: () => setState(...)
    stripped = line.strip()
    if '=>' in stripped and 'setState' in stripped:
        # Check if setState body is on the same line and simple
        arrow_part = stripped.split('=>', 1)[1] if '=>' in stripped else ''
        if '{' not in arrow_part and '}' not in arrow_part:
            return True  # Simple one-liner lambda: => setState(...)
    return False


def check_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    issues = []
    for i, line in enumerate(lines):
        if 'setState(' not in line:
            continue
        # Skip if inline-guarded
        if line_has_guard(line):
            continue
        # Skip sync callbacks
        if is_sync_callback(line):
            continue

        # Check 5 lines before
        context = lines[max(0, i - 5):i]
        has_guard = any(line_has_guard(l) for l in context)

        if not has_guard:
            issues.append((i + 1, line.rstrip()))

    return issues


def main(path):
    total = 0
    file_count = 0
    for root, dirs, files in os.walk(path):
        parts = root.replace('\\', '/').split('/')
        if 'test' in parts:
            continue
        for fname in sorted(files):
            if not fname.endswith('.dart'):
                continue
            fpath = os.path.join(root, fname)
            issues = check_file(fpath)
            if issues:
                rel = os.path.relpath(fpath, '.')
                print(f'{rel}: {len(issues)}')
                for lineno, line in issues:
                    print(f'  L{lineno}: {line.strip()[:80]}')
                file_count += 1
                total += len(issues)
    print(f'\nTOTAL: {total} in {file_count} files')


if __name__ == '__main__':
    search_path = sys.argv[1] if len(sys.argv) > 1 else 'lib'
    main(search_path)
