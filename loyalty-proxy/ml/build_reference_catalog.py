#!/usr/bin/env python3
"""
Build Reference Catalog from Existing Training Data

Reads labeled training images (display-training + counting-training),
crops bounding boxes, computes MobileNetV3-Small embeddings,
and saves to embedding catalog.

Usage:
  python3 build_reference_catalog.py [--dry-run]
"""
import os
import sys
import json
import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

DATA_DIR = SCRIPT_DIR.parent / 'data'
CLASS_MAPPING_FILE = DATA_DIR / 'class-mapping.json'

TRAINING_DIRS = [
    DATA_DIR / 'display-training',
    DATA_DIR / 'counting-training',
]


def load_class_mapping():
    """Load class mapping: productId -> classId"""
    if not CLASS_MAPPING_FILE.exists():
        print(f"[Build] No class mapping at {CLASS_MAPPING_FILE}")
        return {}, {}

    with open(CLASS_MAPPING_FILE) as f:
        mapping = json.load(f)

    # Invert: classId -> productId
    inverted = {v: k for k, v in mapping.items()}
    print(f"[Build] Loaded {len(mapping)} class mappings")
    return mapping, inverted


def parse_yolo_label(label_path, img_width, img_height):
    """
    Parse YOLO label file (class_id cx cy w h format).
    Returns list of (class_id, x1, y1, x2, y2) in pixels.
    """
    boxes = []
    with open(label_path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 5:
                continue
            cls_id = int(parts[0])
            cx, cy, w, h = float(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])

            # Convert from normalized to pixel coords
            x1 = int((cx - w / 2) * img_width)
            y1 = int((cy - h / 2) * img_height)
            x2 = int((cx + w / 2) * img_width)
            y2 = int((cy + h / 2) * img_height)

            # Clamp
            x1 = max(0, x1)
            y1 = max(0, y1)
            x2 = min(img_width, x2)
            y2 = min(img_height, y2)

            if (x2 - x1) >= 10 and (y2 - y1) >= 10:
                boxes.append((cls_id, x1, y1, x2, y2))

    return boxes


def build_catalog(dry_run=False):
    """Build reference catalog from training data"""
    from PIL import Image

    # Import after path setup
    import embedding_catalog as catalog

    mapping, inverted = load_class_mapping()
    if not inverted:
        print("[Build] No class mapping — cannot map class IDs to product IDs")
        return

    # Load embedding model
    print("[Build] Loading MobileNetV3-Small...")
    import torch
    import torchvision.transforms as T
    from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights

    weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
    net = mobilenet_v3_small(weights=weights)
    net.eval()
    net.classifier = torch.nn.Identity()

    transform = T.Compose([
        T.Resize((224, 224)),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])

    print("[Build] Model loaded")

    # Load or create catalog
    catalog.load()
    stats_before = catalog.get_stats()
    print(f"[Build] Catalog before: {stats_before['productCount']} products, {stats_before['totalEmbeddings']} embeddings")

    total_added = 0
    total_errors = 0
    total_images = 0

    for train_dir in TRAINING_DIRS:
        images_dir = train_dir / 'images'
        labels_dir = train_dir / 'labels'

        if not images_dir.exists() or not labels_dir.exists():
            print(f"[Build] Skipping {train_dir.name} — no images/labels dirs")
            continue

        print(f"\n[Build] Processing {train_dir.name}...")

        # Find all label files
        label_files = sorted(labels_dir.glob('*.txt'))
        print(f"[Build] Found {len(label_files)} label files")

        for label_file in label_files:
            # Find corresponding image
            stem = label_file.stem
            img_path = None
            for ext in ['.jpg', '.jpeg', '.png']:
                candidate = images_dir / f"{stem}{ext}"
                if candidate.exists():
                    img_path = candidate
                    break

            if img_path is None:
                continue

            total_images += 1

            try:
                img = Image.open(img_path).convert('RGB')
                img_w, img_h = img.size

                boxes = parse_yolo_label(label_file, img_w, img_h)

                for cls_id, x1, y1, x2, y2 in boxes:
                    product_id = inverted.get(cls_id)
                    if not product_id:
                        continue

                    crop = img.crop((x1, y1, x2, y2))

                    # Compute embedding
                    tensor = transform(crop).unsqueeze(0)
                    with torch.no_grad():
                        features = net(tensor)

                    emb = features.squeeze().numpy()
                    norm = float((emb ** 2).sum() ** 0.5)
                    if norm > 0:
                        emb = emb / norm

                    if not dry_run:
                        catalog.add_embedding(product_id, emb.tolist(), name='')

                    total_added += 1

            except Exception as e:
                total_errors += 1
                if total_errors <= 5:
                    print(f"[Build] Error processing {label_file.name}: {e}")

    if not dry_run:
        catalog.save()

    stats_after = catalog.get_stats()
    print(f"\n[Build] Done!")
    print(f"[Build] Processed {total_images} images, added {total_added} embeddings, {total_errors} errors")
    print(f"[Build] Catalog after: {stats_after['productCount']} products, {stats_after['totalEmbeddings']} embeddings")

    if dry_run:
        print("[Build] DRY RUN — no changes saved")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Build embedding reference catalog')
    parser.add_argument('--dry-run', action='store_true', help='Do not save catalog')
    args = parser.parse_args()

    build_catalog(dry_run=args.dry_run)
