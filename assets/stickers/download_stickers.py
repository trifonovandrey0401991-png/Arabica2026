"""
Download OpenMoji stickers for Arabica messenger.
License: CC BY-SA 4.0 (free for commercial use with attribution)
Attribution: "All emojis designed by OpenMoji. License: CC BY-SA 4.0"

Usage: python download_stickers.py
"""
import os
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/hfg-gmuend/openmoji/master/color/618x618"

# Pack 1: Emotions (20 stickers)
EMOTIONS = {
    "1F600": "grinning",
    "1F603": "smiley",
    "1F604": "smile",
    "1F601": "grin",
    "1F606": "laughing",
    "1F602": "joy_tears",
    "1F923": "rofl",
    "1F609": "wink",
    "1F60D": "heart_eyes",
    "1F618": "kiss",
    "1F970": "smiling_hearts",
    "1F60E": "sunglasses",
    "1F914": "thinking",
    "1F631": "scream",
    "1F622": "cry",
    "1F62D": "sob",
    "1F620": "angry",
    "1F621": "rage",
    "1F62E": "open_mouth",
    "1F634": "sleeping",
}

# Pack 2: Gestures (15 stickers)
GESTURES = {
    "1F44D": "thumbs_up",
    "1F44E": "thumbs_down",
    "1F44F": "clap",
    "1F44B": "wave",
    "1F64F": "pray",
    "1F4AA": "muscle",
    "1F91D": "handshake",
    "270C-FE0F": "victory",
    "1F44C": "ok_hand",
    "1F918": "rock",
    "1F919": "call_me",
    "1F91F": "love_you",
    "1F44A": "fist",
    "1F590-FE0F": "raised_hand",
    "1F64C": "raised_hands",
}

# Pack 3: Food & Objects (15 stickers)
FOOD_OBJECTS = {
    "2615": "coffee",
    "1F370": "cake",
    "1F355": "pizza",
    "1F354": "burger",
    "1F36B": "chocolate",
    "1F382": "birthday_cake",
    "1F37E": "champagne",
    "1F389": "party",
    "2B50": "star",
    "1F525": "fire",
    "1F4AF": "hundred",
    "2764-FE0F": "red_heart",
    "1F494": "broken_heart",
    "1F48E": "gem",
    "1F3C6": "trophy",
}

PACKS = [
    ("emotions", EMOTIONS),
    ("gestures", GESTURES),
    ("food_objects", FOOD_OBJECTS),
]

def download_sticker(code, name, pack_dir):
    """Download a single sticker PNG from OpenMoji GitHub."""
    # Try without -FE0F suffix first (most common)
    clean_code = code.replace("-FE0F", "")
    urls_to_try = [
        f"{BASE_URL}/{code}.png",
        f"{BASE_URL}/{clean_code}.png",
    ]

    filepath = os.path.join(pack_dir, f"{name}.png")
    if os.path.exists(filepath):
        print(f"  [skip] {name}.png already exists")
        return True

    for url in urls_to_try:
        try:
            urllib.request.urlretrieve(url, filepath)
            print(f"  [ok]   {name}.png")
            return True
        except Exception:
            continue

    print(f"  [FAIL] {name}.png (code: {code})")
    return False

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    for pack_name, stickers in PACKS:
        pack_dir = os.path.join(script_dir, pack_name)
        os.makedirs(pack_dir, exist_ok=True)
        print(f"\n=== Pack: {pack_name} ({len(stickers)} stickers) ===")

        ok = 0
        for code, name in stickers.items():
            if download_sticker(code, name, pack_dir):
                ok += 1

        print(f"  Downloaded: {ok}/{len(stickers)}")

    print("\nDone! Upload these folders to the server.")
    print("Attribution: All emojis designed by OpenMoji. License: CC BY-SA 4.0")

if __name__ == "__main__":
    main()
