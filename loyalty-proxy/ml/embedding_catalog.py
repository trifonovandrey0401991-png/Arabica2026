#!/usr/bin/env python3
"""
Embedding Catalog — reference embeddings for product identification.

Stores MobileNetV3-Small feature vectors (576-dim) for each product.
Search by cosine similarity via numpy matrix multiplication.

Storage: data/embedding-catalog/reference_embeddings.json
"""
import json
import os
import numpy as np
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR.parent / 'data'
CATALOG_DIR = DATA_DIR / 'embedding-catalog'
CATALOG_FILE = CATALOG_DIR / 'reference_embeddings.json'

# In-memory catalog
_catalog = None
_matrix = None      # (N, 576) numpy array for fast batch search
_product_ids = []   # parallel array: _product_ids[i] -> product_id for _matrix[i]


def _ensure_dir():
    """Create catalog directory if needed"""
    CATALOG_DIR.mkdir(parents=True, exist_ok=True)


def load():
    """Load catalog from disk into memory"""
    global _catalog, _matrix, _product_ids

    if not CATALOG_FILE.exists():
        _catalog = {'version': 1, 'products': {}}
        _matrix = None
        _product_ids = []
        return False

    with open(CATALOG_FILE) as f:
        _catalog = json.load(f)

    _rebuild_matrix()
    return True


def _rebuild_matrix():
    """Rebuild search matrix from catalog centroids"""
    global _matrix, _product_ids

    products = _catalog.get('products', {})
    if not products:
        _matrix = None
        _product_ids = []
        return

    ids = []
    vectors = []
    for pid, info in products.items():
        centroid = info.get('centroid')
        if centroid and len(centroid) > 0:
            ids.append(pid)
            vectors.append(centroid)

    if vectors:
        _matrix = np.array(vectors, dtype=np.float32)
        # Ensure L2-normalized
        norms = np.linalg.norm(_matrix, axis=1, keepdims=True)
        norms[norms == 0] = 1
        _matrix = _matrix / norms
        _product_ids = ids
    else:
        _matrix = None
        _product_ids = []


def save():
    """Save catalog to disk"""
    if _catalog is None:
        return
    _ensure_dir()
    with open(CATALOG_FILE, 'w') as f:
        json.dump(_catalog, f, ensure_ascii=False)


def search(query_vector, top_k=5, threshold=0.6):
    """
    Search catalog for closest products by cosine similarity.

    Args:
        query_vector: 576-dim numpy array (L2-normalized)
        top_k: max results
        threshold: minimum similarity score

    Returns:
        list of {'productId', 'similarity', 'name'}
    """
    if _matrix is None or len(_product_ids) == 0:
        return []

    # Ensure query is L2-normalized
    query = np.array(query_vector, dtype=np.float32).reshape(1, -1)
    norm = np.linalg.norm(query)
    if norm == 0:
        return []
    query = query / norm

    # Cosine similarity = dot product of L2-normalized vectors
    similarities = (_matrix @ query.T).flatten()

    # Get top-k above threshold
    indices = np.argsort(similarities)[::-1][:top_k]
    results = []
    for idx in indices:
        sim = float(similarities[idx])
        if sim < threshold:
            break
        pid = _product_ids[idx]
        product_info = _catalog['products'].get(pid, {})
        results.append({
            'productId': pid,
            'similarity': round(sim, 4),
            'name': product_info.get('name', ''),
        })

    return results


def add_embedding(product_id, embedding, name=''):
    """
    Add an embedding to the catalog for a product.
    Updates centroid incrementally.

    Args:
        product_id: product identifier
        embedding: 576-dim list or numpy array
        name: human-readable product name
    """
    global _catalog

    if _catalog is None:
        _catalog = {'version': 1, 'products': {}}

    emb = np.array(embedding, dtype=np.float32)
    norm = np.linalg.norm(emb)
    if norm == 0:
        return False
    emb = (emb / norm).tolist()

    products = _catalog['products']

    if product_id in products:
        info = products[product_id]
        embeddings = info.get('embeddings', [])

        # Limit stored embeddings to 20 per product (keep most recent)
        if len(embeddings) >= 20:
            embeddings = embeddings[-19:]

        embeddings.append(emb)
        info['embeddings'] = embeddings
        info['count'] = len(embeddings)

        # Recalculate centroid
        arr = np.array(embeddings, dtype=np.float32)
        centroid = arr.mean(axis=0)
        centroid_norm = np.linalg.norm(centroid)
        if centroid_norm > 0:
            centroid = centroid / centroid_norm
        info['centroid'] = centroid.tolist()

        if name:
            info['name'] = name
    else:
        products[product_id] = {
            'name': name,
            'centroid': emb,
            'embeddings': [emb],
            'count': 1,
        }

    _rebuild_matrix()
    return True


def remove_product(product_id):
    """Remove a product from catalog"""
    if _catalog and product_id in _catalog.get('products', {}):
        del _catalog['products'][product_id]
        _rebuild_matrix()
        return True
    return False


def get_stats():
    """Get catalog statistics"""
    if _catalog is None:
        return {'loaded': False, 'productCount': 0, 'totalEmbeddings': 0}

    products = _catalog.get('products', {})
    total_emb = sum(p.get('count', 0) for p in products.values())

    return {
        'loaded': True,
        'productCount': len(products),
        'totalEmbeddings': total_emb,
        'catalogFile': str(CATALOG_FILE),
        'catalogExists': CATALOG_FILE.exists(),
    }


def get_all_product_ids():
    """Get list of all product IDs in catalog"""
    if _catalog is None:
        return []
    return list(_catalog.get('products', {}).keys())
