#!/usr/bin/env python3
"""
YOLO Inference Server for Cigarette Detection
Persistent HTTP server — loads model once, serves requests via HTTP.
Runs on localhost:5002

Endpoints:
  GET  /health         — check if server and model are ready
  POST /detect         — detectAndCount (find and count products)
  POST /display        — checkDisplay (verify display has expected products)
  POST /display-embed  — checkDisplay via embeddings (1000+ products)
  POST /embed          — compute embedding for one image
  POST /catalog/add    — add reference embedding to catalog
  GET  /catalog/stats  — catalog statistics
"""
import os
import sys
import json
import base64
import threading
import traceback
from io import BytesIO
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle each request in a separate thread"""
    daemon_threads = True

# Suppress ultralytics welcome message
os.environ['YOLO_VERBOSE'] = 'False'

SCRIPT_DIR = Path(__file__).parent
MODELS_DIR = SCRIPT_DIR / 'models'
DEFAULT_MODEL = MODELS_DIR / 'cigarette_detector.pt'
SINGLE_CLASS_MODEL = MODELS_DIR / 'cigarette_detector_single.pt'
DATA_DIR = SCRIPT_DIR.parent / 'data'
CLASS_MAPPING_FILE = DATA_DIR / 'class-mapping.json'

# Feature flag: embedding-based recognition
USE_EMBEDDING = os.environ.get('USE_EMBEDDING_RECOGNITION', 'false').lower() == 'true'

# Load model at startup (keeps in memory for fast inference)
model = None
class_mapping = {}

# Embedding model (MobileNetV3-Small)
embed_model = None
embed_transform = None

# Embedding catalog
embed_catalog = None

# Lock for catalog writes
_catalog_lock = threading.Lock()


def load_model():
    global model
    # If embedding mode and single-class model exists, use it
    model_path = DEFAULT_MODEL
    if USE_EMBEDDING and SINGLE_CLASS_MODEL.exists():
        model_path = SINGLE_CLASS_MODEL
        print(f"[YOLO Server] Embedding mode: using single-class model")

    if not model_path.exists():
        print(f"[YOLO Server] Model not found at {model_path}")
        return False
    try:
        from ultralytics import YOLO
        model = YOLO(str(model_path))
        print(f"[YOLO Server] Model loaded: {model_path}")
        return True
    except Exception as e:
        print(f"[YOLO Server] Failed to load model: {e}")
        return False

def load_class_mapping():
    global class_mapping
    if CLASS_MAPPING_FILE.exists():
        with open(CLASS_MAPPING_FILE) as f:
            class_mapping = json.load(f)
        # Invert: class_id -> product_id
        print(f"[YOLO Server] Loaded {len(class_mapping)} classes")
    else:
        print(f"[YOLO Server] No class mapping at {CLASS_MAPPING_FILE}")


def load_embedding_model():
    """Load MobileNetV3-Small for feature extraction"""
    global embed_model, embed_transform
    try:
        import torch
        import torchvision.transforms as T
        from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights

        weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
        net = mobilenet_v3_small(weights=weights)
        net.eval()

        # Remove classifier head — keep feature extractor only
        # MobileNetV3-Small features output: 576-dim
        net.classifier = torch.nn.Identity()

        embed_model = net
        embed_transform = T.Compose([
            T.Resize((224, 224)),
            T.ToTensor(),
            T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ])

        print("[YOLO Server] MobileNetV3-Small loaded for embeddings (576-dim)")
        return True
    except Exception as e:
        print(f"[YOLO Server] Failed to load embedding model: {e}")
        traceback.print_exc()
        return False


def load_embedding_catalog():
    """Load embedding catalog"""
    global embed_catalog
    try:
        import embedding_catalog as ec
        embed_catalog = ec
        loaded = ec.load()
        stats = ec.get_stats()
        print(f"[YOLO Server] Embedding catalog: {stats['productCount']} products, {stats['totalEmbeddings']} embeddings")
        return True
    except Exception as e:
        print(f"[YOLO Server] Failed to load embedding catalog: {e}")
        traceback.print_exc()
        return False


def compute_embedding(pil_image):
    """Compute 576-dim embedding from PIL Image"""
    import torch
    if embed_model is None or embed_transform is None:
        return None

    img = pil_image.convert('RGB')
    tensor = embed_transform(img).unsqueeze(0)

    with torch.no_grad():
        features = embed_model(tensor)

    # L2-normalize
    emb = features.squeeze().numpy()
    norm = float((emb ** 2).sum() ** 0.5)
    if norm > 0:
        emb = emb / norm
    return emb.tolist()


def detect_and_count(image_path, confidence=0.3, product_id=None):
    """Run detection on image, count detected products"""
    if model is None:
        return {'success': False, 'error': 'Model not loaded'}

    try:
        from PIL import Image
        results = model.predict(
            source=image_path,
            conf=confidence,
            verbose=False,
            save=False,
        )

        detections = []
        if results and len(results) > 0:
            result = results[0]
            if result.boxes is not None:
                # Invert mapping: class_id -> product_id
                id_to_product = {v: k for k, v in class_mapping.items()}

                for box in result.boxes:
                    cls_id = int(box.cls[0])
                    conf = float(box.conf[0])
                    pid = id_to_product.get(cls_id, f'class_{cls_id}')

                    if product_id and pid != product_id:
                        continue

                    xyxy = box.xyxy[0].tolist()
                    detections.append({
                        'productId': pid,
                        'classId': cls_id,
                        'confidence': round(conf, 3),
                        'bbox': {
                            'x1': round(xyxy[0], 1),
                            'y1': round(xyxy[1], 1),
                            'x2': round(xyxy[2], 1),
                            'y2': round(xyxy[3], 1),
                        }
                    })

        # Count by product
        counts = {}
        for d in detections:
            pid = d['productId']
            if pid not in counts:
                counts[pid] = {'count': 0, 'totalConfidence': 0}
            counts[pid]['count'] += 1
            counts[pid]['totalConfidence'] += d['confidence']

        product_counts = []
        for pid, info in counts.items():
            product_counts.append({
                'productId': pid,
                'count': info['count'],
                'avgConfidence': round(info['totalConfidence'] / info['count'], 3),
            })

        return {
            'success': True,
            'detections': detections,
            'productCounts': product_counts,
            'totalDetections': len(detections),
        }
    except Exception as e:
        return {'success': False, 'error': str(e), 'traceback': traceback.format_exc()}

def check_display(image_path, expected_products, confidence=0.3):
    """Check display for expected products"""
    result = detect_and_count(image_path, confidence)
    if not result['success']:
        return result

    detected_ids = set()
    detected_products = []
    for pc in result.get('productCounts', []):
        detected_ids.add(pc['productId'])
        detected_products.append(pc)

    missing = [p for p in expected_products if p not in detected_ids]

    return {
        'success': True,
        'detectedProducts': detected_products,
        'missingProducts': missing,
        'allPresent': len(missing) == 0,
        'totalDetections': result['totalDetections'],
    }


def check_display_embed(image_path, expected_products, confidence=0.3, similarity_threshold=0.6):
    """
    Check display using embedding-based recognition.
    1) YOLO detects all packs (single-class)
    2) Crop each pack, compute embedding
    3) Search catalog for closest product
    4) Return same format as check_display()
    """
    if model is None:
        return {'success': False, 'error': 'YOLO model not loaded'}
    if embed_model is None:
        return {'success': False, 'error': 'Embedding model not loaded'}
    if embed_catalog is None:
        return {'success': False, 'error': 'Embedding catalog not loaded'}

    try:
        from PIL import Image

        # Step 1: YOLO detection (single class = all packs)
        results = model.predict(
            source=image_path,
            conf=confidence,
            verbose=False,
            save=False,
        )

        if not results or len(results) == 0:
            return {
                'success': True,
                'detectedProducts': [],
                'missingProducts': list(expected_products),
                'allPresent': len(expected_products) == 0,
                'totalDetections': 0,
            }

        result = results[0]
        if result.boxes is None or len(result.boxes) == 0:
            return {
                'success': True,
                'detectedProducts': [],
                'missingProducts': list(expected_products),
                'allPresent': len(expected_products) == 0,
                'totalDetections': 0,
            }

        # Step 2: Open image for cropping
        img = Image.open(image_path).convert('RGB')
        img_w, img_h = img.size

        # Step 3: For each detected box, crop and identify
        detected_counts = {}  # product_id -> {'count': N, 'totalConf': F}
        total_detections = 0

        for box in result.boxes:
            xyxy = box.xyxy[0].tolist()
            det_conf = float(box.conf[0])

            x1 = max(0, int(xyxy[0]))
            y1 = max(0, int(xyxy[1]))
            x2 = min(img_w, int(xyxy[2]))
            y2 = min(img_h, int(xyxy[3]))

            # Skip tiny boxes
            if (x2 - x1) < 10 or (y2 - y1) < 10:
                continue

            crop = img.crop((x1, y1, x2, y2))
            emb = compute_embedding(crop)
            if emb is None:
                continue

            # Search catalog
            matches = embed_catalog.search(emb, top_k=1, threshold=similarity_threshold)
            if not matches:
                continue

            match = matches[0]
            pid = match['productId']
            sim = match['similarity']

            if pid not in detected_counts:
                detected_counts[pid] = {'count': 0, 'totalConfidence': 0}
            detected_counts[pid]['count'] += 1
            # Use combined score: YOLO conf * similarity
            detected_counts[pid]['totalConfidence'] += det_conf * sim
            total_detections += 1

        # Step 4: Build response in SAME format as check_display
        detected_products = []
        detected_ids = set()
        for pid, info in detected_counts.items():
            detected_ids.add(pid)
            detected_products.append({
                'productId': pid,
                'count': info['count'],
                'avgConfidence': round(info['totalConfidence'] / info['count'], 3),
            })

        missing = [p for p in expected_products if p not in detected_ids]

        return {
            'success': True,
            'detectedProducts': detected_products,
            'missingProducts': missing,
            'allPresent': len(missing) == 0,
            'totalDetections': total_detections,
        }

    except Exception as e:
        return {'success': False, 'error': str(e), 'traceback': traceback.format_exc()}


class YOLOHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            status = {
                'status': 'ok',
                'modelLoaded': model is not None,
                'modelPath': str(DEFAULT_MODEL),
                'modelExists': DEFAULT_MODEL.exists(),
                'classCount': len(class_mapping),
                'embeddingEnabled': USE_EMBEDDING,
                'embedModelLoaded': embed_model is not None,
                'catalogLoaded': embed_catalog is not None,
            }
            self._send_json(200, status)
        elif self.path == '/catalog/stats':
            if embed_catalog:
                stats = embed_catalog.get_stats()
                self._send_json(200, stats)
            else:
                self._send_json(200, {'loaded': False, 'productCount': 0, 'totalEmbeddings': 0})
        else:
            self._send_json(404, {'error': 'Not found'})

    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else b'{}'
            data = json.loads(body) if body else {}

            if self.path == '/detect':
                self._handle_detect(data)
            elif self.path == '/display':
                self._handle_display(data)
            elif self.path == '/display-embed':
                self._handle_display_embed(data)
            elif self.path == '/embed':
                self._handle_embed(data)
            elif self.path == '/catalog/add':
                self._handle_catalog_add(data)
            elif self.path == '/reload':
                self._handle_reload()
            else:
                self._send_json(404, {'error': 'Not found'})
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'Invalid JSON'})
        except Exception as e:
            self._send_json(500, {'error': str(e), 'traceback': traceback.format_exc()})

    def _save_base64_to_temp(self, image_base64, prefix='yolo'):
        """Save base64 image to temp file, return path"""
        import tempfile
        temp_path = os.path.join(
            tempfile.gettempdir(),
            f'{prefix}_{os.getpid()}_{threading.get_ident()}.jpg'
        )
        img_data = base64.b64decode(image_base64)
        with open(temp_path, 'wb') as f:
            f.write(img_data)
        return temp_path

    def _get_image_path(self, data, prefix='yolo'):
        """Get image path from request data (imagePath or imageBase64)"""
        image_path = data.get('imagePath')
        temp_path = None

        if data.get('imageBase64'):
            temp_path = self._save_base64_to_temp(data['imageBase64'], prefix)
            image_path = temp_path

        return image_path, temp_path

    def _cleanup_temp(self, temp_path):
        """Remove temp file if exists"""
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass

    def _handle_detect(self, data):
        image_path, temp_path = self._get_image_path(data, 'detect')

        if not image_path or not os.path.exists(image_path):
            self._send_json(400, {'error': 'Image path required'})
            return

        try:
            confidence = data.get('confidence', 0.3)
            product_id = data.get('productId')
            result = detect_and_count(image_path, confidence, product_id)
            self._send_json(200, result)
        finally:
            self._cleanup_temp(temp_path)

    def _handle_display(self, data):
        image_path, temp_path = self._get_image_path(data, 'display')

        if not image_path or not os.path.exists(image_path):
            self._send_json(400, {'error': 'Image path required'})
            return

        try:
            expected_products = data.get('expectedProducts', [])
            confidence = data.get('confidence', 0.3)
            result = check_display(image_path, expected_products, confidence)
            self._send_json(200, result)
        finally:
            self._cleanup_temp(temp_path)

    def _handle_display_embed(self, data):
        """Embedding-based display check — same response format as /display"""
        image_path, temp_path = self._get_image_path(data, 'display_embed')

        if not image_path or not os.path.exists(image_path):
            self._send_json(400, {'error': 'Image path required'})
            return

        try:
            expected_products = data.get('expectedProducts', [])
            confidence = data.get('confidence', 0.3)
            similarity_threshold = data.get('similarityThreshold', 0.6)
            result = check_display_embed(image_path, expected_products, confidence, similarity_threshold)
            self._send_json(200, result)
        finally:
            self._cleanup_temp(temp_path)

    def _handle_embed(self, data):
        """Compute embedding for a single image"""
        if embed_model is None:
            self._send_json(500, {'success': False, 'error': 'Embedding model not loaded'})
            return

        image_path, temp_path = self._get_image_path(data, 'embed')

        if not image_path or not os.path.exists(image_path):
            self._send_json(400, {'error': 'Image path required'})
            return

        try:
            from PIL import Image
            img = Image.open(image_path).convert('RGB')
            emb = compute_embedding(img)
            if emb is None:
                self._send_json(500, {'success': False, 'error': 'Failed to compute embedding'})
            else:
                self._send_json(200, {'success': True, 'embedding': emb, 'dimensions': len(emb)})
        finally:
            self._cleanup_temp(temp_path)

    def _handle_catalog_add(self, data):
        """Add reference embedding to catalog"""
        if embed_model is None:
            self._send_json(500, {'success': False, 'error': 'Embedding model not loaded'})
            return
        if embed_catalog is None:
            self._send_json(500, {'success': False, 'error': 'Catalog not loaded'})
            return

        product_id = data.get('productId')
        name = data.get('name', '')

        if not product_id:
            self._send_json(400, {'error': 'productId required'})
            return

        # Accept either pre-computed embedding or image
        embedding = data.get('embedding')
        if not embedding:
            image_path, temp_path = self._get_image_path(data, 'catalog')
            if not image_path or not os.path.exists(image_path):
                self._send_json(400, {'error': 'embedding or imagePath/imageBase64 required'})
                return
            try:
                from PIL import Image
                img = Image.open(image_path).convert('RGB')
                embedding = compute_embedding(img)
            finally:
                self._cleanup_temp(temp_path)

            if embedding is None:
                self._send_json(500, {'success': False, 'error': 'Failed to compute embedding'})
                return

        with _catalog_lock:
            ok = embed_catalog.add_embedding(product_id, embedding, name)
            if ok:
                embed_catalog.save()

        stats = embed_catalog.get_stats()
        self._send_json(200, {
            'success': ok,
            'productId': product_id,
            'catalogProductCount': stats['productCount'],
            'catalogTotalEmbeddings': stats['totalEmbeddings'],
        })

    def _handle_reload(self):
        """Reload model from disk (hot-reload after training)"""
        print("[YOLO Server] Reload requested...")
        was_loaded = model is not None
        success = load_model()
        self._send_json(200, {
            'success': success,
            'modelLoaded': model is not None,
            'wasLoaded': was_loaded,
            'modelExists': DEFAULT_MODEL.exists(),
        })
        if success:
            print("[YOLO Server] Model reloaded successfully!")
        else:
            print("[YOLO Server] Reload failed - model file not found or load error")

    def _send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        # Suppress default request logging
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5002

    print("[YOLO Server] Starting...")
    print(f"[YOLO Server] Model path: {DEFAULT_MODEL}")
    print(f"[YOLO Server] Embedding mode: {USE_EMBEDDING}")

    load_class_mapping()

    if DEFAULT_MODEL.exists() or (USE_EMBEDDING and SINGLE_CLASS_MODEL.exists()):
        print("[YOLO Server] Loading YOLO model (this may take 10-20 seconds)...")
        if load_model():
            print("[YOLO Server] Model loaded successfully!")
        else:
            print("[YOLO Server] Model load failed, server will return errors for inference")
    else:
        print("[YOLO Server] No model file found, server will accept training data only")

    # Load embedding infrastructure if enabled
    if USE_EMBEDDING:
        print("[YOLO Server] Loading embedding model (MobileNetV3-Small)...")
        if load_embedding_model():
            load_embedding_catalog()
        else:
            print("[YOLO Server] Embedding model failed — embedding endpoints will return errors")
    else:
        print("[YOLO Server] Embedding mode OFF — use USE_EMBEDDING_RECOGNITION=true to enable")

    server = ThreadingHTTPServer(('127.0.0.1', port), YOLOHandler)
    print(f"[YOLO Server] Listening on http://127.0.0.1:{port}")
    endpoints = "POST /detect, POST /display, GET /health"
    if USE_EMBEDDING:
        endpoints += ", POST /display-embed, POST /embed, POST /catalog/add, GET /catalog/stats"
    print(f"[YOLO Server] Endpoints: {endpoints}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[YOLO Server] Shutting down...")
        server.server_close()
