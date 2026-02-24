#!/usr/bin/env python3
"""
YOLOv8 Inference Module for Cigarette Detection
================================================

This module provides inference capabilities for detecting and counting
cigarette packs in images using YOLOv8.

Usage:
    python yolo_inference.py --mode detect --image <base64_or_path> --model <model_path>
    python yolo_inference.py --mode display --image <base64_or_path> --expected <product_ids>
    python yolo_inference.py --mode train --data <data_yaml_path>

Requirements:
    pip install ultralytics opencv-python pillow numpy
"""

import argparse
import base64
import json
import os
import sys
from io import BytesIO
from pathlib import Path

# Suppress ultralytics welcome message
os.environ['YOLO_VERBOSE'] = 'False'

try:
    from ultralytics import YOLO
    import numpy as np
    from PIL import Image
    YOLO_AVAILABLE = True
except ImportError:
    YOLO_AVAILABLE = False


# Default paths
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR.parent / 'data'
MODELS_DIR = SCRIPT_DIR / 'models'
DEFAULT_MODEL = MODELS_DIR / 'cigarette_detector.pt'
CLASS_MAPPING_FILE = DATA_DIR / 'class-mapping.json'


def load_class_mapping(mapping_file=None):
    """Load product ID to class ID mapping"""
    target = Path(mapping_file) if mapping_file else CLASS_MAPPING_FILE
    if target.exists():
        with open(target, 'r') as f:
            return json.load(f)
    return {}


def get_reverse_mapping(mapping_file=None):
    """Get class ID to product ID mapping"""
    mapping = load_class_mapping(mapping_file)
    return {v: k for k, v in mapping.items()}


def decode_image(image_input):
    """
    Decode image from base64 string or file path

    Args:
        image_input: Base64 string or file path

    Returns:
        PIL.Image or None
    """
    try:
        # Try as file path first
        if os.path.exists(image_input):
            return Image.open(image_input)

        # Try as base64
        if ',' in image_input:
            # Remove data URL prefix if present
            image_input = image_input.split(',')[1]

        image_data = base64.b64decode(image_input)
        return Image.open(BytesIO(image_data))
    except Exception as e:
        print(json.dumps({
            'success': False,
            'error': f'Failed to decode image: {str(e)}'
        }))
        return None


def detect_and_count(image_input, model_path=None, product_id=None, confidence_threshold=0.5):
    """
    Detect and count cigarette packs in image

    Args:
        image_input: Base64 string or file path
        model_path: Path to YOLO model (optional)
        product_id: Filter results to specific product (optional)
        confidence_threshold: Minimum confidence for detection

    Returns:
        dict with detection results
    """
    if not YOLO_AVAILABLE:
        return {
            'success': False,
            'error': 'YOLOv8 not installed. Run: pip install ultralytics',
            'count': 0,
            'confidence': 0,
            'boxes': []
        }

    # Load model
    model_file = Path(model_path) if model_path else DEFAULT_MODEL

    if not model_file.exists():
        return {
            'success': False,
            'error': f'Model not found: {model_file}. Train a model first.',
            'count': 0,
            'confidence': 0,
            'boxes': [],
            'model_missing': True
        }

    try:
        model = YOLO(str(model_file))
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to load model: {str(e)}',
            'count': 0,
            'confidence': 0,
            'boxes': []
        }

    # Decode image
    image = decode_image(image_input)
    if image is None:
        return {
            'success': False,
            'error': 'Failed to decode image',
            'count': 0,
            'confidence': 0,
            'boxes': []
        }

    # Convert to RGB if necessary
    if image.mode != 'RGB':
        image = image.convert('RGB')

    # Run inference
    try:
        results = model(image, verbose=False, conf=confidence_threshold)
    except Exception as e:
        return {
            'success': False,
            'error': f'Inference failed: {str(e)}',
            'count': 0,
            'confidence': 0,
            'boxes': []
        }

    # Process results
    reverse_mapping = get_reverse_mapping()
    detections = []
    total_confidence = 0

    for result in results:
        boxes = result.boxes
        if boxes is None:
            continue

        for i, box in enumerate(boxes):
            class_id = int(box.cls[0])
            confidence = float(box.conf[0])
            xyxy = box.xyxy[0].tolist()

            # Get product ID from class mapping
            detected_product_id = reverse_mapping.get(class_id, f'unknown_{class_id}')

            # Filter by product_id if specified
            if product_id and detected_product_id != product_id:
                continue

            # Normalize coordinates to 0-1 range
            img_width, img_height = image.size
            x1, y1, x2, y2 = xyxy

            detection = {
                'classId': class_id,
                'productId': detected_product_id,
                'confidence': round(confidence, 4),
                'box': {
                    'x1': round(x1 / img_width, 4),
                    'y1': round(y1 / img_height, 4),
                    'x2': round(x2 / img_width, 4),
                    'y2': round(y2 / img_height, 4),
                },
                'boxPixels': {
                    'x1': int(x1),
                    'y1': int(y1),
                    'x2': int(x2),
                    'y2': int(y2),
                }
            }

            detections.append(detection)
            total_confidence += confidence

    count = len(detections)
    avg_confidence = total_confidence / count if count > 0 else 0

    return {
        'success': True,
        'count': count,
        'confidence': round(avg_confidence, 4),
        'boxes': detections,
        'imageSize': {'width': image.size[0], 'height': image.size[1]}
    }


def check_display(image_input, expected_products, model_path=None, confidence_threshold=0.3):
    """
    Check if expected products are present in display image

    Args:
        image_input: Base64 string or file path
        expected_products: List of expected product IDs
        model_path: Path to YOLO model (optional)
        confidence_threshold: Minimum confidence for detection

    Returns:
        dict with display check results
    """
    if not YOLO_AVAILABLE:
        return {
            'success': False,
            'error': 'YOLOv8 not installed. Run: pip install ultralytics',
            'missingProducts': expected_products,
            'detectedProducts': []
        }

    # First run detection
    detection_result = detect_and_count(
        image_input,
        model_path,
        confidence_threshold=confidence_threshold
    )

    if not detection_result['success']:
        return {
            'success': False,
            'error': detection_result.get('error', 'Detection failed'),
            'missingProducts': expected_products,
            'detectedProducts': []
        }

    # Get unique detected product IDs
    detected_ids = set()
    for box in detection_result['boxes']:
        detected_ids.add(box['productId'])

    # Find missing products
    expected_set = set(expected_products) if expected_products else set()
    detected_in_expected = detected_ids.intersection(expected_set)
    missing = list(expected_set - detected_ids)

    # Group detections by product
    products_summary = {}
    for box in detection_result['boxes']:
        pid = box['productId']
        if pid not in products_summary:
            products_summary[pid] = {
                'productId': pid,
                'count': 0,
                'avgConfidence': 0,
                'confidences': []
            }
        products_summary[pid]['count'] += 1
        products_summary[pid]['confidences'].append(box['confidence'])

    # Calculate average confidence per product
    detected_products = []
    for pid, summary in products_summary.items():
        avg_conf = sum(summary['confidences']) / len(summary['confidences'])
        detected_products.append({
            'productId': pid,
            'count': summary['count'],
            'avgConfidence': round(avg_conf, 4),
            'isExpected': pid in expected_set
        })

    return {
        'success': True,
        'totalDetected': detection_result['count'],
        'detectedProducts': detected_products,
        'missingProducts': missing,
        'expectedCount': len(expected_set),
        'foundExpectedCount': len(detected_in_expected),
        'isComplete': len(missing) == 0 if expected_products else True,
        # Добавляем raw boxes для positive samples (обучение YOLO)
        'boxes': detection_result.get('boxes', [])
    }


def export_training_data(output_dir):
    """
    Export training data in YOLO format with train/val split (80/20)

    Args:
        output_dir: Output directory for YOLO dataset
    """
    import shutil
    import random

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Создаём train/val структуру
    train_images_dir = output_path / 'train' / 'images'
    train_labels_dir = output_path / 'train' / 'labels'
    val_images_dir = output_path / 'val' / 'images'
    val_labels_dir = output_path / 'val' / 'labels'

    for d in [train_images_dir, train_labels_dir, val_images_dir, val_labels_dir]:
        d.mkdir(parents=True, exist_ok=True)

    # CIG-1: Читаем из ВСЕХ dataset-директорий (новые типизированные + legacy)
    source_dirs = [
        (DATA_DIR / 'display-training', 'images', 'labels'),
        (DATA_DIR / 'counting-training', 'images', 'labels'),
        (DATA_DIR / 'cigarette-training-images', None, None),  # legacy flat structure
    ]

    all_samples = []  # [(img_path, label_path_or_none)]

    for base_dir, img_subdir, lbl_subdir in source_dirs:
        img_dir = base_dir / img_subdir if img_subdir else base_dir
        lbl_dir = base_dir / lbl_subdir if lbl_subdir else DATA_DIR / 'cigarette-training-labels'

        if not img_dir.exists():
            continue

        for img_file in img_dir.glob('*.jpg'):
            label_file = lbl_dir / f'{img_file.stem}.txt'
            all_samples.append((img_file, label_file if label_file.exists() else None))

        # Также PNG файлы
        for img_file in img_dir.glob('*.png'):
            label_file = lbl_dir / f'{img_file.stem}.txt'
            all_samples.append((img_file, label_file if label_file.exists() else None))

    if not all_samples:
        return {'success': False, 'error': 'No training images found in any dataset directory'}

    # CIG-2: Разделяем 80% train / 20% val
    random.shuffle(all_samples)
    split_idx = int(len(all_samples) * 0.8)
    train_samples = all_samples[:split_idx]
    val_samples = all_samples[split_idx:]

    copied_train = 0
    copied_val = 0

    for img_path, lbl_path in train_samples:
        shutil.copy(img_path, train_images_dir / img_path.name)
        if lbl_path:
            shutil.copy(lbl_path, train_labels_dir / lbl_path.name)
        copied_train += 1

    for img_path, lbl_path in val_samples:
        shutil.copy(img_path, val_images_dir / img_path.name)
        if lbl_path:
            shutil.copy(lbl_path, val_labels_dir / lbl_path.name)
        copied_val += 1

    # FIX-4: Строим актуальный class-mapping из трёх источников:
    # 1. Существующие typed class-mapping.json (сохраняем старые ID)
    # 2. samples.json — берём productId всех одобренных образцов
    # 3. Назначаем новые ID продуктам, которых ещё нет в маппинге
    class_mapping = {}
    for base_dir, _, _ in source_dirs:
        typed_mapping_file = base_dir / 'class-mapping.json'
        if typed_mapping_file.exists():
            typed_mapping = load_class_mapping(str(typed_mapping_file))
            class_mapping.update(typed_mapping)
    # Fallback на общий если typed пустой
    if not class_mapping:
        class_mapping = load_class_mapping()

    # Собираем product IDs из samples.json (все одобренные образцы)
    all_product_ids = set()
    for base_dir, _, _ in source_dirs:
        samples_file = base_dir / 'samples.json'
        if samples_file.exists():
            try:
                with open(samples_file, 'r', encoding='utf-8') as f:
                    samples_data = json.load(f)
                for s in (samples_data if isinstance(samples_data, list) else []):
                    pid = s.get('productId')
                    if pid:
                        all_product_ids.add(pid)
            except Exception:
                pass

    # Назначаем ID новым продуктам (детерминированно по алфавиту)
    for pid in sorted(all_product_ids):
        if pid not in class_mapping:
            class_mapping[pid] = len(class_mapping)

    # Пишем актуальный class-mapping в главный файл (для yolo_server)
    if class_mapping:
        try:
            with open(CLASS_MAPPING_FILE, 'w', encoding='utf-8') as f:
                json.dump(class_mapping, f, indent=2, ensure_ascii=False)
        except Exception:
            pass

    num_classes = max(len(class_mapping), 1)
    class_names = ['unknown'] * num_classes
    for product_id, class_id in class_mapping.items():
        if 0 <= class_id < num_classes:
            class_names[class_id] = product_id

    data_yaml = {
        'path': str(output_path.absolute()),
        'train': 'train/images',
        'val': 'val/images',
        'nc': num_classes,
        'names': class_names
    }

    import yaml
    with open(output_path / 'data.yaml', 'w') as f:
        yaml.dump(data_yaml, f, default_flow_style=False, allow_unicode=True)

    return {
        'success': True,
        'output_dir': str(output_path),
        'train_images': copied_train,
        'val_images': copied_val,
        'total_images': len(all_samples),
        'num_classes': num_classes,
        'class_mapping': class_mapping,
        'data_yaml': str(output_path / 'data.yaml')
    }


def train_model(data_yaml, epochs=100, imgsz=640, batch=16, output_dir=None):
    """
    Train YOLOv8 model on cigarette detection data

    Args:
        data_yaml: Path to data.yaml file
        epochs: Number of training epochs
        imgsz: Image size for training
        batch: Batch size
        output_dir: Output directory for model
    """
    if not YOLO_AVAILABLE:
        return {
            'success': False,
            'error': 'YOLOv8 not installed. Run: pip install ultralytics'
        }

    if not Path(data_yaml).exists():
        return {
            'success': False,
            'error': f'Data YAML not found: {data_yaml}'
        }

    try:
        # Start with pretrained YOLOv8n (nano - fastest)
        model = YOLO('yolov8n.pt')

        # Train
        results = model.train(
            data=data_yaml,
            epochs=epochs,
            imgsz=imgsz,
            batch=batch,
            project=str(output_dir or MODELS_DIR),
            name='cigarette_detector',
            exist_ok=True
        )

        # Copy best model to default location
        best_model = Path(results.save_dir) / 'weights' / 'best.pt'
        if best_model.exists():
            import shutil
            MODELS_DIR.mkdir(exist_ok=True)
            shutil.copy(best_model, DEFAULT_MODEL)

        # FIX-6: Извлекаем метрики качества модели
        metrics = {}
        try:
            rd = results.results_dict if hasattr(results, 'results_dict') else {}
            metrics = {
                'mAP50':     round(float(rd.get('metrics/mAP50(B)',     rd.get('metrics/mAP50',     0))), 4),
                'mAP50_95':  round(float(rd.get('metrics/mAP50-95(B)',  rd.get('metrics/mAP50-95',  0))), 4),
                'precision': round(float(rd.get('metrics/precision(B)', rd.get('metrics/precision',  0))), 4),
                'recall':    round(float(rd.get('metrics/recall(B)',    rd.get('metrics/recall',     0))), 4),
            }
        except Exception:
            pass  # метрики необязательны

        return {
            'success': True,
            'model_path': str(DEFAULT_MODEL),
            'results_dir': str(results.save_dir),
            'metrics': metrics,
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Training failed: {str(e)}'
        }


def main():
    parser = argparse.ArgumentParser(description='YOLOv8 Cigarette Detection')
    parser.add_argument('--mode', type=str, required=True,
                       choices=['detect', 'display', 'train', 'export', 'status'],
                       help='Operation mode')
    parser.add_argument('--image', type=str, help='Image (base64 or path)')
    parser.add_argument('--model', type=str, help='Model path')
    parser.add_argument('--product-id', type=str, help='Product ID filter')
    parser.add_argument('--expected', type=str, help='Expected products (comma-separated)')
    parser.add_argument('--data', type=str, help='Data YAML path for training')
    parser.add_argument('--output', type=str, help='Output directory')
    parser.add_argument('--epochs', type=int, default=100, help='Training epochs')
    parser.add_argument('--confidence', type=float, default=0.5, help='Confidence threshold')
    parser.add_argument('--class-mapping', type=str, help='Path to class-mapping.json (typed training)')

    args = parser.parse_args()

    result = {}

    if args.mode == 'status':
        result = {
            'yolo_available': YOLO_AVAILABLE,
            'model_exists': DEFAULT_MODEL.exists(),
            'model_path': str(DEFAULT_MODEL),
            'class_mapping_exists': CLASS_MAPPING_FILE.exists(),
            'num_classes': len(load_class_mapping()) if CLASS_MAPPING_FILE.exists() else 0
        }

    elif args.mode == 'detect':
        if not args.image:
            result = {'success': False, 'error': 'Image required for detection'}
        else:
            result = detect_and_count(
                args.image,
                args.model,
                args.product_id,
                args.confidence
            )

    elif args.mode == 'display':
        if not args.image:
            result = {'success': False, 'error': 'Image required for display check'}
        else:
            expected = args.expected.split(',') if args.expected else []
            result = check_display(
                args.image,
                expected,
                args.model,
                args.confidence
            )

    elif args.mode == 'export':
        if not args.output:
            result = {'success': False, 'error': 'Output directory required'}
        else:
            result = export_training_data(args.output)

    elif args.mode == 'train':
        if not args.data:
            result = {'success': False, 'error': 'Data YAML required for training'}
        else:
            result = train_model(
                args.data,
                args.epochs,
                output_dir=args.output
            )

    print(json.dumps(result))


if __name__ == '__main__':
    main()
