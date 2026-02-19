-- Wave 8: AI Modules → PostgreSQL
-- Tables for z-report, cigarette-vision, shift-ai
-- Run: sudo -u postgres psql -d arabica_db -f create_wave8_tables.sql

-- Z-Report Templates
CREATE TABLE IF NOT EXISTS z_report_templates (
  id VARCHAR(255) PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Z-Report Training Samples
CREATE TABLE IF NOT EXISTS z_report_training_samples (
  id VARCHAR(255) PRIMARY KEY,
  shop_id VARCHAR(255),
  template_id VARCHAR(255),
  data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_zrt_samples_shop ON z_report_training_samples(shop_id);
CREATE INDEX IF NOT EXISTS idx_zrt_samples_template ON z_report_training_samples(template_id);

-- Cigarette Vision Samples (legacy training samples)
CREATE TABLE IF NOT EXISTS cigarette_samples (
  id VARCHAR(255) PRIMARY KEY,
  product_id VARCHAR(255),
  type VARCHAR(50),
  shop_address TEXT,
  data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cig_samples_product ON cigarette_samples(product_id);
CREATE INDEX IF NOT EXISTS idx_cig_samples_type ON cigarette_samples(type);

-- Shift AI Annotations
CREATE TABLE IF NOT EXISTS shift_ai_annotations (
  id VARCHAR(255) PRIMARY KEY,
  product_id VARCHAR(255),
  barcode VARCHAR(255),
  shop_address TEXT,
  data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sai_annotations_product ON shift_ai_annotations(product_id);
CREATE INDEX IF NOT EXISTS idx_sai_annotations_barcode ON shift_ai_annotations(barcode);

-- Singletons go into existing app_settings table:
-- key = 'z_report_learned_patterns'
-- key = 'cigarette_vision_settings'
-- key = 'shift_ai_settings'
-- (app_settings table already exists from previous migrations)
