#!/usr/bin/env python3
"""
OCR Microservice for Coffee Machine Counter Recognition
Uses EasyOCR (neural network) with OpenCV preprocessing
Runs as HTTP server on localhost:5001

Strategy for finding the CORRECT counter number among many:
  1. Keyword detection: find "Guaranteecounter", "Варка" etc and extract nearby number
  2. Spatial proximity: numbers near keywords get boosted score
  3. Digit-count scoring: counter readings are typically 4-6 digits
  4. Multi-variant consensus: numbers found in multiple preprocessing variants score higher
"""
import os
import sys
import json
import gc
import re
import math
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler

import cv2
import numpy as np

print("[OCR Server] Starting...")
print("[OCR Server] Loading EasyOCR model (this may take 20-30 seconds)...")
import easyocr
reader = easyocr.Reader(['ru', 'en'], gpu=False, verbose=False)
print("[OCR Server] Model loaded successfully!")

# Keywords that indicate the counter reading line
COUNTER_KEYWORDS = {
    # BW3/BW4 (English/transliterated)
    'guarantee': 5, 'guaranteecounter': 10, 'arantee': 4, 'ounter': 3,
    'counter': 3, 'teecounter': 5, 'garantie': 5,
    # BW4 (Russian/transliterated from OCR)
    'гарант': 5, 'гарантия': 8, 'rapant': 3, 'tapaht': 3, 'garantia': 5,
    # WMF (Russian brewing counter)
    'варка': 8, 'варк': 5, 'bapka': 5, 'bapk': 3, 'brewing': 5,
}


def preprocess_image(img, preset="standard"):
    """Generate multiple preprocessed versions"""
    variants = []
    h, w = img.shape[:2]

    max_dim = 800
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        img_small = cv2.resize(img, (int(w * scale), int(h * scale)))
    else:
        img_small = img.copy()

    max_dim_hi = 1200
    if max(h, w) > max_dim_hi:
        scale = max_dim_hi / max(h, w)
        img_hi = cv2.resize(img, (int(w * scale), int(h * scale)))
    else:
        img_hi = img.copy()

    if preset == "invert_lcd":
        inv_hi = cv2.bitwise_not(img_hi)
        variants.append(("inv_hires", inv_hi))
        variants.append(("original", img_small.copy()))
        gray = cv2.cvtColor(img_small, cv2.COLOR_BGR2GRAY)
        inv_gray = cv2.bitwise_not(gray)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(inv_gray)
        variants.append(("inv_clahe", cv2.cvtColor(enhanced, cv2.COLOR_GRAY2BGR)))
        # Extra: high-res inverted CLAHE for difficult angles
        gray_hi = cv2.cvtColor(img_hi, cv2.COLOR_BGR2GRAY)
        inv_gray_hi = cv2.bitwise_not(gray_hi)
        clahe_hi = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
        enhanced_hi = clahe_hi.apply(inv_gray_hi)
        variants.append(("inv_clahe_hi", cv2.cvtColor(enhanced_hi, cv2.COLOR_GRAY2BGR)))
    elif preset == "standard_resize":
        variants.append(("original", img_small.copy()))
        gray = cv2.cvtColor(img_small, cv2.COLOR_BGR2GRAY)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        variants.append(("clahe", cv2.cvtColor(enhanced, cv2.COLOR_GRAY2BGR)))
        inverted = cv2.bitwise_not(img_small)
        variants.append(("inverted", inverted))
    else:
        variants.append(("original", img_small.copy()))
        gray = cv2.cvtColor(img_small, cv2.COLOR_BGR2GRAY)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        variants.append(("clahe", cv2.cvtColor(enhanced, cv2.COLOR_GRAY2BGR)))
        variants.append(("hires", img_hi.copy()))

    return variants


def bbox_center(bbox):
    """Get center of bounding box [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]"""
    xs = [p[0] for p in bbox]
    ys = [p[1] for p in bbox]
    return (sum(xs) / len(xs), sum(ys) / len(ys))


def bbox_distance(bbox1, bbox2):
    """Euclidean distance between bbox centers"""
    c1 = bbox_center(bbox1)
    c2 = bbox_center(bbox2)
    return math.sqrt((c1[0] - c2[0])**2 + (c1[1] - c2[1])**2)


def find_keyword_numbers(results):
    """
    Find numbers that are near counter-related keywords.
    Returns dict: value -> keyword_score
    """
    keyword_results = []  # (bbox, keyword, score)
    number_results = []   # (bbox, value, conf)

    for bbox, text, conf in results:
        text_lower = text.lower().strip()
        # Check if this is a keyword
        for kw, kw_score in COUNTER_KEYWORDS.items():
            if kw in text_lower:
                keyword_results.append((bbox, kw, kw_score))
                break

        # Check if this contains a number
        nums = re.findall(r'\d[\d\s,.]*\d|\d+', text)
        for n in nums:
            clean = re.sub(r'[\s,.]', '', n)
            if clean.isdigit() and int(clean) > 100:
                number_results.append((bbox, int(clean), float(conf)))

    # For each keyword, find nearby numbers and boost them
    keyword_boosted = {}
    for kw_bbox, kw_text, kw_score in keyword_results:
        for num_bbox, num_val, num_conf in number_results:
            dist = bbox_distance(kw_bbox, num_bbox)
            # Numbers on the same line or very close get the full boost
            if dist < 300:  # pixels
                proximity_factor = max(0.1, 1.0 - dist / 300.0)
                boost = kw_score * proximity_factor
                if num_val not in keyword_boosted or boost > keyword_boosted[num_val]:
                    keyword_boosted[num_val] = boost

    # Also: if keyword text CONTAINS a number directly (e.g., "Guaranteecounter 144777")
    for bbox, text, conf in results:
        text_lower = text.lower().strip()
        for kw, kw_score in COUNTER_KEYWORDS.items():
            if kw in text_lower:
                # Extract numbers from the SAME text block
                nums = re.findall(r'\d[\d\s,.]*\d|\d+', text)
                for n in nums:
                    clean = re.sub(r'[\s,.]', '', n)
                    if clean.isdigit() and int(clean) > 100:
                        val = int(clean)
                        # Direct association = max boost
                        boost = kw_score * 2.0
                        if val not in keyword_boosted or boost > keyword_boosted[val]:
                            keyword_boosted[val] = boost

    return keyword_boosted


def is_date_pattern(val):
    """Check if number looks like a date (DDMMYYYY or YYYYMMDD)"""
    s = str(val)
    if len(s) == 8:
        # DDMMYYYY
        dd, mm = int(s[:2]), int(s[2:4])
        if 1 <= dd <= 31 and 1 <= mm <= 12:
            return True
        # YYYYMMDD
        mm2, dd2 = int(s[4:6]), int(s[6:8])
        if 1 <= dd2 <= 31 and 1 <= mm2 <= 12:
            return True
    return False


def recognize(image_path, preset="standard", expected_range=None):
    """Main recognition function"""
    img = cv2.imread(image_path)
    if img is None:
        return {"error": f"Cannot read image: {image_path}", "success": False}

    # Only use keyword detection for standard/standard_resize presets
    # For invert_lcd (WMF), EasyOCR reads text too poorly for keyword matching
    use_keywords = preset != "invert_lcd"

    variants = preprocess_image(img, preset)
    del img
    gc.collect()

    all_numbers = {}  # value -> {"confidence": float, "variant": str, "count": int, "keyword_boost": float}
    raw_texts = []

    for vname, vimg in variants:
        tmp_path = f"/tmp/counter-ocr/easy_{os.getpid()}_{vname}.jpg"
        try:
            cv2.imwrite(tmp_path, vimg)
            del vimg

            results = reader.readtext(tmp_path)

            # Extract keyword-boosted numbers (only for readable presets)
            kw_boosted = find_keyword_numbers(results) if use_keywords else {}

            # Extract all numbers
            for bbox, text, conf in results:
                nums = re.findall(r'\d[\d\s,.]*\d|\d+', text)
                for n in nums:
                    clean = re.sub(r'[\s,.]', '', n)
                    if clean.isdigit():
                        val = int(clean)
                        # Skip dates (DDMMYYYY patterns)
                        if val > 100 and not is_date_pattern(val):
                            if val not in all_numbers:
                                all_numbers[val] = {
                                    "confidence": float(conf),
                                    "variant": vname,
                                    "count": 0,
                                    "keyword_boost": 0.0,
                                }
                            entry = all_numbers[val]
                            entry["count"] += 1
                            if float(conf) > entry["confidence"]:
                                entry["confidence"] = float(conf)
                                entry["variant"] = vname
                            if val in kw_boosted:
                                entry["keyword_boost"] = max(entry["keyword_boost"], kw_boosted[val])

            texts = [r[1] for r in results if r[2] > 0.2]
            raw_texts.append({"variant": vname, "texts": texts[:10]})

            del results
        except Exception as e:
            raw_texts.append({"variant": vname, "error": str(e)})
        finally:
            try:
                os.unlink(tmp_path)
            except:
                pass
        gc.collect()

    # Score each number
    def composite_score(val, info):
        conf = info["confidence"]
        digits = len(str(val))
        count = info["count"]
        kw_boost = info["keyword_boost"]

        # Base score from confidence
        score = conf

        # Digit bonus (counter readings are 4-6 digits)
        if digits >= 6:
            score *= 3.0
        elif digits >= 5:
            score *= 2.5
        elif digits >= 4:
            score *= 2.0
        elif digits >= 3:
            score *= 1.0
        else:
            score *= 0.3

        # Multi-variant consensus bonus
        if count >= 3:
            score *= 1.5
        elif count >= 2:
            score *= 1.2

        # Keyword proximity bonus (most important signal!)
        if kw_boost > 0:
            score += kw_boost * 2.0

        # Expected range bonus (from machine intelligence)
        if expected_range:
            range_min = expected_range.get("min", 0)
            range_max = expected_range.get("max", float("inf"))
            if range_min <= val <= range_max:
                score *= 1.5

        return score

    sorted_nums = sorted(
        all_numbers.items(),
        key=lambda x: -composite_score(x[0], x[1])
    )

    numbers_list = [
        {
            "value": val,
            "confidence": round(info["confidence"], 3),
            "variant": info["variant"],
            "score": round(composite_score(val, info), 3),
            "keyword_boost": round(info["keyword_boost"], 2),
            "count": info["count"],
        }
        for val, info in sorted_nums[:10]
    ]

    best = sorted_nums[0] if sorted_nums else None

    return {
        "success": True,
        "numbers": numbers_list,
        "bestNumber": best[0] if best else None,
        "bestConfidence": best[1]["confidence"] if best else 0,
        "bestVariant": best[1]["variant"] if best else None,
        "rawTexts": raw_texts,
    }


def preprocess_zreport(img):
    """Generate preprocessing variants optimized for thermal paper Z-reports"""
    variants = []
    h, w = img.shape[:2]

    max_dim = 1200
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        img_resized = cv2.resize(img, (int(w * scale), int(h * scale)))
    else:
        img_resized = img.copy()

    # Variant 1: Original
    variants.append(("original", img_resized.copy()))

    # Variant 2: CLAHE contrast enhancement (thermal paper often low contrast)
    gray = cv2.cvtColor(img_resized, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    variants.append(("clahe", cv2.cvtColor(enhanced, cv2.COLOR_GRAY2BGR)))

    # Variant 3: Adaptive threshold (binary, good for faded receipts)
    thresh = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                    cv2.THRESH_BINARY, 31, 10)
    variants.append(("adaptive_thresh", cv2.cvtColor(thresh, cv2.COLOR_GRAY2BGR)))

    # Variant 4: High-res if image was large
    if max(h, w) > 1200:
        max_dim_hi = 1800
        scale_hi = max_dim_hi / max(h, w)
        img_hi = cv2.resize(img, (int(w * scale_hi), int(h * scale_hi)))
        variants.append(("hires", img_hi))

    return variants


def recognize_text(image_path):
    """
    Full text recognition for Z-reports.
    Returns complete text in reading order (top-to-bottom, left-to-right).
    """
    img = cv2.imread(image_path)
    if img is None:
        return {"error": f"Cannot read image: {image_path}", "success": False}

    variants = preprocess_zreport(img)
    del img
    gc.collect()

    best_text = ""
    best_char_count = 0
    all_variant_results = []

    for vname, vimg in variants:
        tmp_path = f"/tmp/counter-ocr/zr_{os.getpid()}_{vname}.jpg"
        try:
            cv2.imwrite(tmp_path, vimg)
            del vimg

            results = reader.readtext(tmp_path)

            if not results:
                all_variant_results.append({"variant": vname, "text": "", "lines": 0})
                continue

            # Sort by Y coordinate (top of bbox) to get reading order
            def sort_key(item):
                bbox = item[0]
                y_top = min(p[1] for p in bbox)
                x_left = min(p[0] for p in bbox)
                return (y_top, x_left)

            results.sort(key=sort_key)

            # Group into lines: items with similar Y coordinates
            lines = []
            current_line = []
            current_y = None
            line_threshold = 15  # pixels

            for bbox, text, conf in results:
                if conf < 0.1:
                    continue
                y_center = sum(p[1] for p in bbox) / 4
                if current_y is None or abs(y_center - current_y) > line_threshold:
                    if current_line:
                        current_line.sort(key=lambda x: min(p[0] for p in x[0]))
                        line_text = " ".join(item[1] for item in current_line)
                        lines.append(line_text)
                    current_line = [(bbox, text, conf)]
                    current_y = y_center
                else:
                    current_line.append((bbox, text, conf))

            if current_line:
                current_line.sort(key=lambda x: min(p[0] for p in x[0]))
                line_text = " ".join(item[1] for item in current_line)
                lines.append(line_text)

            full_text = "\n".join(lines)
            char_count = len(full_text.replace(" ", "").replace("\n", ""))

            all_variant_results.append({
                "variant": vname,
                "lines": len(lines),
                "chars": char_count
            })

            if char_count > best_char_count:
                best_char_count = char_count
                best_text = full_text

        except Exception as e:
            all_variant_results.append({"variant": vname, "error": str(e)})
        finally:
            try:
                os.unlink(tmp_path)
            except:
                pass
        gc.collect()

    return {
        "success": True,
        "text": best_text,
        "charCount": best_char_count,
        "lineCount": best_text.count("\n") + 1 if best_text else 0,
        "variants": all_variant_results
    }


class OCRHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "engine": "easyocr", "languages": ["ru", "en"]}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/ocr":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                data = json.loads(body)

                image_path = data.get("imagePath")
                preset = data.get("preset", "standard")
                expected_range = data.get("expectedRange")  # {"min": N, "max": N} from intelligence

                if not image_path or not os.path.exists(image_path):
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "imagePath required and must exist"}).encode())
                    return

                result = recognize(image_path, preset, expected_range)

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e), "traceback": traceback.format_exc()}).encode())
        elif self.path == "/ocr-text":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                data = json.loads(body)

                image_path = data.get("imagePath")

                if not image_path or not os.path.exists(image_path):
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "imagePath required and must exist"}).encode())
                    return

                result = recognize_text(image_path)

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e), "traceback": traceback.format_exc()}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5001
    server = HTTPServer(("127.0.0.1", port), OCRHandler)
    print(f"[OCR Server] Listening on http://127.0.0.1:{port}")
    print(f"[OCR Server] Endpoints: POST /ocr, POST /ocr-text, GET /health")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[OCR Server] Shutting down...")
        server.server_close()
