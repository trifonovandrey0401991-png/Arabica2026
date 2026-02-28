"""
Comprehensive Flutter code audit:
1. setState without mounted check (async & sync)
2. Controllers without dispose
3. Hardcoded colors
4. Hardcoded URLs
"""
import os, re, sys

def find_setstate_issues(lib_dir):
    """Find all setState calls without mounted check, categorize by async/sync."""
    results = []

    for root, dirs, files in os.walk(lib_dir):
        parts = root.replace('\\', '/').split('/')
        if 'test' in parts:
            continue
        for fname in sorted(files):
            if not fname.endswith('.dart'):
                continue
            fpath = os.path.join(root, fname).replace('\\', '/')
            try:
                with open(fpath, 'r', encoding='utf-8') as f:
                    content = f.read()
            except:
                continue

            lines = content.split('\n')

            for i, line in enumerate(lines):
                if 'setState(' not in line:
                    continue

                line_num = i + 1
                stripped = line.strip()

                # Skip comments
                if stripped.startswith('//') or stripped.startswith('*'):
                    continue

                # Skip if already guarded on same line
                if 'mounted' in line:
                    continue

                # Check previous 5 lines for mounted guard
                has_guard = False
                for j in range(max(0, i-5), i):
                    if 'mounted' in lines[j] and ('if' in lines[j] or 'return' in lines[j]):
                        has_guard = True
                        break
                if has_guard:
                    continue

                # Determine async context by scanning backwards for the enclosing method
                is_async = False
                has_await_before = False
                brace_depth = 0

                # Look for await between this line and method start
                for j in range(i - 1, max(0, i - 100) - 1, -1):
                    l = lines[j]
                    brace_depth += l.count('}') - l.count('{')
                    if brace_depth > 0:
                        # Found method boundary
                        if 'async' in l or (j > 0 and 'async' in lines[j-1]):
                            is_async = True
                        break
                    if 'await ' in l:
                        has_await_before = True

                # Simple sync callback pattern (safe)
                is_simple_callback = False
                if '=>' in line and 'setState' in line:
                    # e.g. onChanged: (_) => setState(() {}),
                    is_simple_callback = True

                if is_simple_callback and not is_async and not has_await_before:
                    ctx = 'sync-callback'
                elif is_async or has_await_before:
                    ctx = 'ASYNC'
                else:
                    ctx = 'sync'

                results.append((fpath, line_num, stripped[:120], ctx))

    return results


def find_missing_dispose(lib_dir):
    """Find controllers declared as fields without corresponding dispose() call."""
    results = []
    ctrl_types = ['TextEditingController', 'ScrollController', 'AnimationController', 'TabController']
    # Match field declarations like: final _nameController = TextEditingController();
    # or: late TextEditingController _nameController;
    field_re = re.compile(
        r'(?:final|late\s+final?|late)\s+(?:' + '|'.join(ctrl_types) + r')\s+(\w+)|'
        r'(?:final|late\s+final?)\s+(\w+)\s*=\s*(?:' + '|'.join(ctrl_types) + r')\('
    )

    for root, dirs, files in os.walk(lib_dir):
        parts = root.replace('\\', '/').split('/')
        if 'test' in parts:
            continue
        for fname in sorted(files):
            if not fname.endswith('.dart'):
                continue
            fpath = os.path.join(root, fname).replace('\\', '/')
            try:
                with open(fpath, 'r', encoding='utf-8') as f:
                    content = f.read()
            except:
                continue

            lines = content.split('\n')

            # Find class-level controller declarations
            controllers = []
            in_class = False
            class_brace_depth = 0

            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*') or stripped.startswith('import'):
                    continue

                # Detect controller field by name patterns
                for ct in ctrl_types:
                    if ct in line:
                        # Try to extract variable name
                        # Pattern 1: final TextEditingController _name = ...
                        m = re.search(rf'(?:final|late)\s+{ct}\s+(_?\w+)', line)
                        if m:
                            controllers.append((i + 1, m.group(1), ct, stripped[:100]))
                            continue
                        # Pattern 2: final _name = TextEditingController(...)
                        m = re.search(rf'(?:final|late\s+final)\s+(_?\w+)\s*=\s*{ct}\(', line)
                        if m:
                            controllers.append((i + 1, m.group(1), ct, stripped[:100]))
                            continue
                        # Pattern 3: TextEditingController _name = ...
                        m = re.search(rf'{ct}\s+(_?\w+)\s*=', line)
                        if m:
                            # Make sure this is a field (indented by 2-4 spaces, not inside a method)
                            indent = len(line) - len(line.lstrip())
                            if indent <= 4:
                                controllers.append((i + 1, m.group(1), ct, stripped[:100]))

            if not controllers:
                continue

            # Check which controllers are disposed
            for ln, name, ctype, code in controllers:
                dispose_call = f'{name}.dispose()'
                if dispose_call not in content:
                    # Also check for super.dispose() covering it (unlikely but possible)
                    # Check if it's a local variable (inside a method) vs field
                    # Local variables in showDialog etc don't need dispose if dialog handles it
                    line_text = lines[ln - 1]
                    indent = len(line_text) - len(line_text.lstrip())
                    # Fields are typically at indent 2 (inside class)
                    is_field = indent <= 4
                    # Check if inside a method (indent > 4 usually means local var)
                    if is_field:
                        results.append((fpath, ln, name, ctype, code))

    return results


def find_hardcoded_colors(lib_dir):
    """Find Color(0x...) outside of app_colors.dart and theme files."""
    results = []
    pattern = re.compile(r'Color\(0x([0-9A-Fa-f]+)\)')
    skip_files = {'app_colors.dart', 'app_theme.dart'}

    for root, dirs, files in os.walk(lib_dir):
        parts = root.replace('\\', '/').split('/')
        if 'test' in parts:
            continue
        for fname in sorted(files):
            if not fname.endswith('.dart') or fname in skip_files:
                continue
            fpath = os.path.join(root, fname).replace('\\', '/')
            try:
                with open(fpath, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
            except:
                continue

            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*'):
                    continue
                matches = pattern.findall(line)
                if matches:
                    for m in matches:
                        results.append((fpath, i + 1, f'Color(0x{m})', stripped[:120]))

    return results


def find_hardcoded_urls(lib_dir):
    """Find hardcoded URLs/IPs instead of ApiConstants."""
    results = []
    url_re = re.compile(r"""(?:['"])(\s*https?://[^'"]+)""")
    skip_files = {'api_constants.dart'}
    safe_domains = ['example.com', 'schemas.android', 'schemas.microsoft',
                    'w3.org', 'schema.org', 'pub.dev', 'fonts.google',
                    'googleapis.com', 'apple.com', 'mozilla.org', 'dart.dev',
                    'flutter.dev', 'github.com']

    for root, dirs, files in os.walk(lib_dir):
        parts = root.replace('\\', '/').split('/')
        if 'test' in parts:
            continue
        for fname in sorted(files):
            if not fname.endswith('.dart') or fname in skip_files:
                continue
            fpath = os.path.join(root, fname).replace('\\', '/')
            try:
                with open(fpath, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
            except:
                continue

            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*'):
                    continue
                matches = url_re.findall(line)
                for m in matches:
                    m = m.strip()
                    if any(d in m for d in safe_domains):
                        continue
                    results.append((fpath, i + 1, m, stripped[:120]))

    return results


if __name__ == '__main__':
    lib_dir = sys.argv[1] if len(sys.argv) > 1 else 'lib'

    # 1. setState issues
    print('=' * 80)
    print('1. setState WITHOUT mounted CHECK')
    print('=' * 80)
    ss_results = find_setstate_issues(lib_dir)

    async_r = [r for r in ss_results if r[3] == 'ASYNC']
    sync_r = [r for r in ss_results if r[3] == 'sync']
    callback_r = [r for r in ss_results if r[3] == 'sync-callback']

    print(f'\n  ASYNC (DANGEROUS): {len(async_r)}')
    print(f'  Sync (needs review): {len(sync_r)}')
    print(f'  Sync callbacks (safe): {len(callback_r)}')

    if async_r:
        print('\n  --- ASYNC (dangerous - after await) ---')
        for fpath, ln, code, ctx in sorted(async_r, key=lambda x: x[0]):
            print(f'  {fpath}:{ln}')
            print(f'    {code}')

    if sync_r:
        print('\n  --- SYNC (review needed) ---')
        for fpath, ln, code, ctx in sorted(sync_r, key=lambda x: x[0]):
            print(f'  {fpath}:{ln}  {code}')

    if callback_r:
        print('\n  --- SYNC CALLBACKS (safe) ---')
        for fpath, ln, code, ctx in sorted(callback_r, key=lambda x: x[0]):
            print(f'  {fpath}:{ln}  {code}')

    # 2. Missing dispose
    print('\n' + '=' * 80)
    print('2. CONTROLLERS WITHOUT dispose()')
    print('=' * 80)
    disp_results = find_missing_dispose(lib_dir)
    print(f'\n  Total: {len(disp_results)} controllers missing dispose')
    for fpath, ln, name, ctype, code in disp_results:
        print(f'  {fpath}:{ln}  {ctype} {name}')
        print(f'    {code}')

    # 3. Hardcoded colors
    print('\n' + '=' * 80)
    print('3. HARDCODED COLORS (should use AppColors)')
    print('=' * 80)
    clr_results = find_hardcoded_colors(lib_dir)
    print(f'\n  Total: {len(clr_results)} instances')
    by_file = {}
    for fpath, ln, color, code in clr_results:
        by_file.setdefault(fpath, []).append((ln, color, code))
    for fpath in sorted(by_file):
        print(f'\n  {fpath}:')
        for ln, color, code in by_file[fpath]:
            print(f'    L{ln}: {color}  — {code[:80]}')

    # 4. Hardcoded URLs
    print('\n' + '=' * 80)
    print('4. HARDCODED URLs/IPs (should use ApiConstants)')
    print('=' * 80)
    url_results = find_hardcoded_urls(lib_dir)
    print(f'\n  Total: {len(url_results)} instances')
    for fpath, ln, url, code in url_results:
        print(f'  {fpath}:{ln}  {url}')
        print(f'    {code}')
