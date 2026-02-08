const fs = require('fs');
const path = require('path');

const REVIEWS_DIR = '/var/www/reviews';

if (!fs.existsSync(REVIEWS_DIR)) {
  fs.mkdirSync(REVIEWS_DIR, { recursive: true });
}

function setupReviewsAPI(app) {
  // ===== REVIEWS =====

  app.get('/api/reviews', async (req, res) => {
    try {
      console.log('GET /api/reviews');
      const { shopAddress, rating, fromDate, toDate } = req.query;
      const reviews = [];

      if (fs.existsSync(REVIEWS_DIR)) {
        const files = fs.readdirSync(REVIEWS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(REVIEWS_DIR, file), 'utf8');
            const review = JSON.parse(content);

            if (shopAddress && review.shopAddress !== shopAddress) continue;
            if (rating && review.rating !== parseInt(rating)) continue;
            if (fromDate && review.createdAt < fromDate) continue;
            if (toDate && review.createdAt > toDate) continue;

            reviews.push(review);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reviews.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, reviews });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/reviews', async (req, res) => {
    try {
      const review = req.body;
      console.log('POST /api/reviews:', review.shopAddress, review.rating);

      if (!review.id) {
        review.id = `review_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      review.createdAt = review.createdAt || new Date().toISOString();

      const filePath = path.join(REVIEWS_DIR, `${review.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(review, null, 2), 'utf8');

      res.json({ success: true, review });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/reviews/:reviewId', async (req, res) => {
    try {
      const { reviewId } = req.params;
      console.log('GET /api/reviews/:reviewId', reviewId);

      const filePath = path.join(REVIEWS_DIR, `${reviewId}.json`);

      if (fs.existsSync(filePath)) {
        const review = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, review });
      } else {
        res.status(404).json({ success: false, error: 'Review not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/reviews/:reviewId', async (req, res) => {
    try {
      const { reviewId } = req.params;
      const updates = req.body;
      console.log('PUT /api/reviews/:reviewId', reviewId);

      const filePath = path.join(REVIEWS_DIR, `${reviewId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Review not found' });
      }

      const review = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...review, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, review: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/reviews/:reviewId', async (req, res) => {
    try {
      const { reviewId } = req.params;
      console.log('DELETE /api/reviews/:reviewId', reviewId);

      const filePath = path.join(REVIEWS_DIR, `${reviewId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Review not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REVIEWS STATS =====

  app.get('/api/reviews/stats/:shopAddress', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('GET /api/reviews/stats:', shopAddress);

      const reviews = [];

      if (fs.existsSync(REVIEWS_DIR)) {
        const files = fs.readdirSync(REVIEWS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(REVIEWS_DIR, file), 'utf8');
            const review = JSON.parse(content);

            if (review.shopAddress === shopAddress) {
              reviews.push(review);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      const totalReviews = reviews.length;
      const averageRating = totalReviews > 0
        ? reviews.reduce((sum, r) => sum + (r.rating || 0), 0) / totalReviews
        : 0;

      const ratingDistribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
      reviews.forEach(r => {
        if (r.rating >= 1 && r.rating <= 5) {
          ratingDistribution[r.rating]++;
        }
      });

      res.json({
        success: true,
        stats: {
          shopAddress,
          totalReviews,
          averageRating: Math.round(averageRating * 10) / 10,
          ratingDistribution
        }
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Reviews API initialized');
}

module.exports = { setupReviewsAPI };
