# Quick Guide: Fixing Unguarded setState Calls

## TL;DR

**Rule:** Always use `if (mounted)` before `setState()` in async code.

---

## When to Add Guards

### ✅ ALWAYS guard setState in these situations:

1. **After `await`**
```dart
final data = await api.getData();
if (mounted) setState(() => _data = data);  // ✅ REQUIRED
```

2. **In `.then()` callbacks**
```dart
api.getData().then((data) {
  if (mounted) setState(() => _data = data);  // ✅ REQUIRED
});
```

3. **In `Future.delayed()`**
```dart
Future.delayed(Duration(seconds: 1), () {
  if (mounted) setState(() => _loading = false);  // ✅ REQUIRED
});
```

4. **In `Timer` callbacks**
```dart
Timer(Duration(seconds: 1), () {
  if (mounted) setState(() => _tick++);  // ✅ REQUIRED
});
```

### ❌ DON'T need guards in these situations:

1. **In synchronous event handlers**
```dart
onPressed: () => setState(() => _selected = true),  // ✅ OK (sync)
```

2. **In initState/build**
```dart
@override
void initState() {
  super.initState();
  setState(() => _value = widget.initialValue);  // ✅ OK (init)
}
```

3. **Immediately after checking mounted**
```dart
if (!mounted) return;
setState(() => _data = data);  // ✅ OK (just checked)
```

---

## Fix Patterns

### Pattern 1: Simple async function
```dart
// BEFORE ❌
Future<void> loadData() async {
  final data = await api.getData();
  setState(() => _data = data);  // BAD
}

// AFTER ✅
Future<void> loadData() async {
  final data = await api.getData();
  if (mounted) {
    setState(() => _data = data);
  }
}
```

### Pattern 2: Multiple awaits
```dart
// BEFORE ❌
Future<void> loadMultiple() async {
  final users = await api.getUsers();
  setState(() => _users = users);  // BAD

  final posts = await api.getPosts();
  setState(() => _posts = posts);  // BAD
}

// AFTER ✅
Future<void> loadMultiple() async {
  final users = await api.getUsers();
  if (!mounted) return;  // Early exit
  setState(() => _users = users);

  final posts = await api.getPosts();
  if (!mounted) return;  // Early exit
  setState(() => _posts = posts);
}
```

### Pattern 3: Error handling
```dart
// BEFORE ❌
Future<void> loadWithError() async {
  try {
    final data = await api.getData();
    setState(() {  // BAD
      _data = data;
      _error = null;
    });
  } catch (e) {
    setState(() => _error = e.toString());  // BAD
  }
}

// AFTER ✅
Future<void> loadWithError() async {
  try {
    final data = await api.getData();
    if (mounted) {
      setState(() {
        _data = data;
        _error = null;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() => _error = e.toString());
    }
  }
}
```

### Pattern 4: Timer/Delayed
```dart
// BEFORE ❌
void startTimer() {
  Timer.periodic(Duration(seconds: 1), (timer) {
    setState(() => _seconds++);  // BAD
  });
}

// AFTER ✅
Timer? _timer;

void startTimer() {
  _timer = Timer.periodic(Duration(seconds: 1), (timer) {
    if (mounted) {
      setState(() => _seconds++);
    }
  });
}

@override
void dispose() {
  _timer?.cancel();  // Clean up
  super.dispose();
}
```

### Pattern 5: Callback hell
```dart
// BEFORE ❌
api.getData().then((data) {
  setState(() => _data = data);  // BAD
  return api.getDetails(data.id);
}).then((details) {
  setState(() => _details = details);  // BAD
});

// AFTER ✅ (Better: use async/await)
Future<void> loadData() async {
  final data = await api.getData();
  if (!mounted) return;
  setState(() => _data = data);

  final details = await api.getDetails(data.id);
  if (!mounted) return;
  setState(() => _details = details);
}
```

---

## Common Mistakes

### ❌ Mistake 1: Guard outside setState
```dart
if (mounted) {
  final data = await api.getData();  // WRONG - await BEFORE check
  setState(() => _data = data);
}
```

**Fix:** Check AFTER async operations
```dart
final data = await api.getData();
if (mounted) {  // RIGHT - check AFTER await
  setState(() => _data = data);
}
```

### ❌ Mistake 2: Forgetting multiple setState
```dart
final data = await api.getData();
if (mounted) {
  setState(() => _data = data);
}
setState(() => _loading = false);  // FORGOT guard here!
```

**Fix:** Guard ALL setState after async
```dart
final data = await api.getData();
if (mounted) {
  setState(() {
    _data = data;
    _loading = false;  // Both in same setState
  });
}
```

### ❌ Mistake 3: Using wrong guard
```dart
if (widget.mounted) setState(() => ...);  // WRONG - widget doesn't have mounted
```

**Fix:** Use `mounted` directly (it's a State property)
```dart
if (mounted) setState(() => ...);  // RIGHT
```

---

## Search & Replace Helper

To find unguarded setState in a file:

```bash
# Search for setState after await
grep -B5 'setState(' your_file.dart | grep -B5 'await'

# Or use the analysis script
cd c:\Users\Admin\arabica2026
python find_critical_setstate.py
```

---

## VSCode Snippet

Add to your VSCode snippets for quick fixes:

```json
{
  "setState with mounted guard": {
    "prefix": "stm",
    "body": [
      "if (mounted) {",
      "  setState(() {",
      "    $1",
      "  });",
      "}"
    ],
    "description": "setState with mounted guard"
  }
}
```

Usage: Type `stm` then Tab

---

## Testing After Fixes

1. **Run analyzer:**
   ```bash
   flutter analyze
   ```

2. **Run tests:**
   ```bash
   flutter test
   ```

3. **Manual test:**
   - Navigate to page
   - Trigger async action
   - Immediately navigate back
   - Check console for errors

---

## Why This Matters

**Without mounted guard:**
```
setState() called after dispose(): _MyWidgetState#abc123
This error happens if you call setState() on a State object for a widget
that no longer appears in the widget tree.
```

**With mounted guard:**
- No crash
- No error
- Graceful handling of disposed widgets

---

## Project Stats (as of 2026-02-19)

- **Total unguarded setState:** 1,006
- **Critical (async):** 371
- **Top offender:** group_info_page.dart (23 calls)

See `SETSTATE_ANALYSIS_REPORT.md` for full details.

---

## Boy Scout Rule

When touching ANY file:
1. Fix its setState issues
2. Don't need to fix the whole project
3. Just fix what you touch

Over time, the codebase will improve naturally.
