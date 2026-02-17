-- ============================================
-- Arabica DB Schema — PostgreSQL 16
-- Создано: 2026-02-17
-- Запуск: PGPASSWORD=arabica2026secure psql -U arabica_app -h localhost -d arabica_db -f db_schema.sql
-- ============================================

-- ============================================
-- ВОЛНА 1: Ядро (shops, employees, suppliers, settings)
-- ============================================

CREATE TABLE IF NOT EXISTS shops (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT UNIQUE NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  referral_code INTEGER,
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  position TEXT,
  department TEXT,
  email TEXT,
  is_admin BOOLEAN DEFAULT false,
  is_manager BOOLEAN DEFAULT false,
  employee_name TEXT,
  preferred_work_days TEXT[],
  preferred_shops TEXT[],
  shift_preferences JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY,
  referral_code INTEGER,
  name TEXT NOT NULL,
  inn TEXT,
  legal_type TEXT,
  phone TEXT,
  email TEXT,
  contact_person TEXT,
  payment_type TEXT,
  shop_deliveries TEXT,
  delivery_days TEXT[],
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS points_settings (
  id TEXT PRIMARY KEY,
  category TEXT UNIQUE NOT NULL,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shop_settings (
  shop_address TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS automation_state (
  scheduler_name TEXT PRIMARY KEY,
  state JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ВОЛНА 2: Клиенты, заказы, отзывы
-- ============================================

CREATE TABLE IF NOT EXISTS clients (
  phone TEXT PRIMARY KEY,
  name TEXT,
  client_name TEXT,
  fcm_token TEXT,
  referred_by TEXT,
  referred_at TIMESTAMPTZ,
  is_admin BOOLEAN DEFAULT false,
  employee_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  order_number INTEGER,
  client_phone TEXT,
  client_name TEXT,
  shop_address TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total_price NUMERIC,
  comment TEXT,
  status TEXT DEFAULT 'pending',
  accepted_by TEXT,
  rejected_by TEXT,
  rejection_reason TEXT,
  rejected_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_orders_client ON orders(client_phone);
CREATE INDEX IF NOT EXISTS idx_orders_shop ON orders(shop_address);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_date ON orders(created_at);

CREATE TABLE IF NOT EXISTS reviews (
  id TEXT PRIMARY KEY,
  client_phone TEXT,
  client_name TEXT,
  shop_address TEXT,
  review_type TEXT,
  review_text TEXT,
  messages JSONB DEFAULT '[]',
  has_unread_from_client BOOLEAN DEFAULT false,
  has_unread_from_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reviews_shop ON reviews(shop_address);

-- ============================================
-- ВОЛНА 3: Отчёты
-- ============================================

CREATE TABLE IF NOT EXISTS shift_reports (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_id TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shop_name TEXT,
  shift_type TEXT,
  shift_label TEXT,
  status TEXT DEFAULT 'pending',
  answers JSONB DEFAULT '[]',
  rating INTEGER,
  date TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  submitted_at TIMESTAMPTZ,
  deadline TIMESTAMPTZ,
  review_deadline TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  confirmed_by_admin TEXT,
  failed_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  completed_by TEXT,
  is_synced BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_shift_reports_date ON shift_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_shift_reports_shop ON shift_reports(shop_address);
CREATE INDEX IF NOT EXISTS idx_shift_reports_status ON shift_reports(status);
CREATE INDEX IF NOT EXISTS idx_shift_reports_employee ON shift_reports(employee_phone);

CREATE TABLE IF NOT EXISTS shift_handover_reports (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shop_name TEXT,
  shift_type TEXT,
  status TEXT DEFAULT 'pending',
  answers JSONB DEFAULT '[]',
  rating INTEGER,
  date TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  deadline TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  review_deadline TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  confirmed_by_admin TEXT,
  failed_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  completed_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_shift_handover_date ON shift_handover_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_shift_handover_shop ON shift_handover_reports(shop_address);
CREATE INDEX IF NOT EXISTS idx_shift_handover_status ON shift_handover_reports(status);

CREATE TABLE IF NOT EXISTS recount_reports (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_phone TEXT,
  employee_id TEXT,
  shop_address TEXT,
  shop_name TEXT,
  shift_type TEXT,
  status TEXT DEFAULT 'pending',
  answers JSONB DEFAULT '[]',
  admin_rating INTEGER,
  admin_name TEXT,
  rated_at TIMESTAMPTZ,
  date TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  deadline TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  review_deadline TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  completed_by TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  duration INTEGER,
  expired_at TIMESTAMPTZ,
  photo_verifications JSONB DEFAULT '[]',
  saved_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_recount_date ON recount_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_recount_shop ON recount_reports(shop_address);
CREATE INDEX IF NOT EXISTS idx_recount_status ON recount_reports(status);

CREATE TABLE IF NOT EXISTS envelope_reports (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shift_type TEXT,
  status TEXT DEFAULT 'pending',
  date TEXT,
  ooo_z_report_photo_url TEXT,
  ooo_revenue NUMERIC,
  ooo_cash NUMERIC,
  ooo_expenses JSONB DEFAULT '[]',
  ooo_envelope_photo_url TEXT,
  ip_z_report_photo_url TEXT,
  ip_revenue NUMERIC,
  ip_cash NUMERIC,
  expenses JSONB DEFAULT '[]',
  ip_envelope_photo_url TEXT,
  rating INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  deadline TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  confirmed_by_admin TEXT,
  failed_at TIMESTAMPTZ,
  completed_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_envelope_date ON envelope_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_envelope_shop ON envelope_reports(shop_address);
CREATE INDEX IF NOT EXISTS idx_envelope_status ON envelope_reports(status);

CREATE TABLE IF NOT EXISTS coffee_machine_reports (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shift_type TEXT,
  date DATE,
  readings JSONB DEFAULT '[]',
  computer_number INTEGER,
  computer_photo_url TEXT,
  sum_of_machines INTEGER,
  has_discrepancy BOOLEAN DEFAULT false,
  discrepancy_amount INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending',
  rating INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  deadline TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  confirmed_by_admin TEXT,
  rejected_at TIMESTAMPTZ,
  rejected_by_admin TEXT,
  reject_reason TEXT,
  failed_at TIMESTAMPTZ,
  completed_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cm_reports_date ON coffee_machine_reports(date);
CREATE INDEX IF NOT EXISTS idx_cm_reports_shop ON coffee_machine_reports(shop_address);

CREATE TABLE IF NOT EXISTS rko_reports (
  id TEXT PRIMARY KEY,
  file_name TEXT,
  original_name TEXT,
  employee_name TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shop_name TEXT,
  date DATE,
  amount NUMERIC,
  rko_type TEXT,
  shift_type TEXT,
  file_path TEXT,
  status TEXT DEFAULT 'pending',
  rating INTEGER,
  confirmed_by TEXT,
  confirmed_at TIMESTAMPTZ,
  rejected_by TEXT,
  rejected_at TIMESTAMPTZ,
  reject_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rko_date ON rko_reports(date);
CREATE INDEX IF NOT EXISTS idx_rko_shop ON rko_reports(shop_address);
CREATE INDEX IF NOT EXISTS idx_rko_status ON rko_reports(status);
CREATE INDEX IF NOT EXISTS idx_rko_employee ON rko_reports(employee_name);
CREATE INDEX IF NOT EXISTS idx_rko_type ON rko_reports(rko_type);

-- ============================================
-- ВОЛНА 4: Центральный реестр баллов + посещаемость
-- ============================================

CREATE TABLE IF NOT EXISTS efficiency_penalties (
  id TEXT PRIMARY KEY,
  type TEXT DEFAULT 'employee',
  entity_id TEXT,
  entity_name TEXT,
  shop_address TEXT,
  employee_name TEXT,
  employee_phone TEXT,
  category TEXT NOT NULL,
  category_name TEXT,
  date DATE NOT NULL,
  shift_type TEXT,
  points NUMERIC NOT NULL,
  reason TEXT,
  source_id TEXT,
  source_type TEXT,
  late_minutes INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_eff_penalties_date ON efficiency_penalties(date);
CREATE INDEX IF NOT EXISTS idx_eff_penalties_employee ON efficiency_penalties(entity_id);
CREATE INDEX IF NOT EXISTS idx_eff_penalties_shop ON efficiency_penalties(shop_address);
CREATE INDEX IF NOT EXISTS idx_eff_penalties_category ON efficiency_penalties(category);
CREATE INDEX IF NOT EXISTS idx_eff_penalties_source ON efficiency_penalties(source_id);

CREATE TABLE IF NOT EXISTS attendance (
  id TEXT PRIMARY KEY,
  employee_name TEXT,
  employee_phone TEXT,
  shop_address TEXT,
  shop_name TEXT,
  shift_type TEXT,
  status TEXT DEFAULT 'pending',
  "timestamp" TIMESTAMPTZ,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  distance NUMERIC,
  is_on_time BOOLEAN,
  late_minutes INTEGER,
  marked_at TIMESTAMPTZ,
  deadline TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(created_at);
CREATE INDEX IF NOT EXISTS idx_attendance_employee ON attendance(employee_name);
CREATE INDEX IF NOT EXISTS idx_attendance_shop ON attendance(shop_address);

CREATE TABLE IF NOT EXISTS bonus_penalties (
  id TEXT PRIMARY KEY,
  employee_id TEXT,
  employee_name TEXT,
  type TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  comment TEXT,
  admin_name TEXT,
  month TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bonus_month ON bonus_penalties(month);
CREATE INDEX IF NOT EXISTS idx_bonus_employee ON bonus_penalties(employee_id);

-- ============================================
-- ВОЛНА 5: Задачи и расписание
-- ============================================

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  response_type TEXT,
  deadline TIMESTAMPTZ,
  created_by TEXT,
  attachments TEXT[],
  month TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tasks_month ON tasks(month);

CREATE TABLE IF NOT EXISTS task_assignments (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id),
  assignee_id TEXT,
  assignee_name TEXT,
  assignee_phone TEXT,
  assignee_role TEXT,
  status TEXT DEFAULT 'pending',
  deadline TIMESTAMPTZ,
  response_text TEXT,
  response_photos TEXT[],
  responded_at TIMESTAMPTZ,
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  review_comment TEXT,
  expired_at TIMESTAMPTZ,
  viewed_by_admin BOOLEAN DEFAULT false,
  viewed_by_admin_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_task_assign_task ON task_assignments(task_id);
CREATE INDEX IF NOT EXISTS idx_task_assign_assignee ON task_assignments(assignee_id);
CREATE INDEX IF NOT EXISTS idx_task_assign_status ON task_assignments(status);

CREATE TABLE IF NOT EXISTS recurring_tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  response_type TEXT,
  days_of_week INTEGER[],
  start_time TEXT,
  end_time TEXT,
  reminder_times TEXT[],
  assignees JSONB,
  is_paused BOOLEAN DEFAULT false,
  created_by TEXT,
  supplier_id TEXT,
  shop_id TEXT,
  supplier_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recurring_task_instances (
  id TEXT PRIMARY KEY,
  recurring_task_id TEXT,
  assignee_id TEXT,
  assignee_name TEXT,
  assignee_phone TEXT,
  date DATE,
  deadline TIMESTAMPTZ,
  reminder_times TEXT[],
  status TEXT DEFAULT 'pending',
  response_text TEXT,
  response_photos TEXT[],
  completed_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  is_recurring BOOLEAN DEFAULT true,
  title TEXT,
  description TEXT,
  response_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_recurring_inst_date ON recurring_task_instances(date);
CREATE INDEX IF NOT EXISTS idx_recurring_inst_task ON recurring_task_instances(recurring_task_id);
CREATE INDEX IF NOT EXISTS idx_recurring_inst_assignee ON recurring_task_instances(assignee_id);

CREATE TABLE IF NOT EXISTS work_schedule_entries (
  id TEXT PRIMARY KEY,
  employee_id TEXT,
  employee_name TEXT,
  shop_address TEXT,
  date DATE NOT NULL,
  shift_type TEXT,
  month TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_schedule_month ON work_schedule_entries(month);
CREATE INDEX IF NOT EXISTS idx_schedule_employee ON work_schedule_entries(employee_id);
CREATE INDEX IF NOT EXISTS idx_schedule_date ON work_schedule_entries(date);

-- ============================================
-- ВОЛНА 6: Чаты
-- ============================================

CREATE TABLE IF NOT EXISTS employee_chats (
  id TEXT PRIMARY KEY,
  type TEXT,
  name TEXT,
  participants TEXT[],
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  chat_id TEXT REFERENCES employee_chats(id),
  sender_phone TEXT,
  sender_name TEXT,
  text TEXT,
  image_url TEXT,
  read_by TEXT[],
  "timestamp" TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_chat_msg_chat ON chat_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_msg_time ON chat_messages("timestamp");

CREATE TABLE IF NOT EXISTS client_messages (
  id TEXT PRIMARY KEY,
  client_phone TEXT,
  channel TEXT NOT NULL,
  shop_address TEXT,
  text TEXT,
  image_url TEXT,
  sender_type TEXT,
  sender_name TEXT,
  sender_phone TEXT,
  is_read_by_client BOOLEAN DEFAULT false,
  is_read_by_admin BOOLEAN DEFAULT false,
  data JSONB,
  "timestamp" TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_client_msg_phone ON client_messages(client_phone);
CREATE INDEX IF NOT EXISTS idx_client_msg_channel ON client_messages(channel);
CREATE INDEX IF NOT EXISTS idx_client_msg_time ON client_messages("timestamp");

-- ============================================
-- ВОЛНА 7: Остальное
-- ============================================

CREATE TABLE IF NOT EXISTS auth_sessions (
  id SERIAL PRIMARY KEY,
  phone TEXT NOT NULL,
  session_token TEXT UNIQUE NOT NULL,
  employee_id TEXT,
  is_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_phone ON auth_sessions(phone);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_token ON auth_sessions(session_token);

CREATE TABLE IF NOT EXISTS auth_pins (
  phone TEXT PRIMARY KEY,
  pin_hash TEXT NOT NULL,
  hash_type TEXT DEFAULT 'bcrypt',
  salt TEXT,
  failed_attempts INTEGER DEFAULT 0,
  locked_until TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS fcm_tokens (
  phone TEXT PRIMARY KEY,
  token TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS job_applications (
  id TEXT PRIMARY KEY,
  full_name TEXT,
  phone TEXT,
  preferred_shift TEXT,
  shop_addresses TEXT[],
  is_viewed BOOLEAN DEFAULT false,
  viewed_at TIMESTAMPTZ,
  viewed_by TEXT,
  status TEXT DEFAULT 'new',
  admin_notes TEXT,
  status_updated_at TIMESTAMPTZ,
  notes_updated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recipes (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS training_articles (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS test_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS test_results (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recount_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shift_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shift_handover_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS envelope_questions (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS coffee_machine_templates (
  id TEXT PRIMARY KEY,
  name TEXT,
  preset TEXT,
  data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS coffee_machine_shop_configs (
  shop_address TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS main_cash (
  shop_address TEXT PRIMARY KEY,
  ooo_balance NUMERIC DEFAULT 0,
  ip_balance NUMERIC DEFAULT 0,
  total_balance NUMERIC DEFAULT 0,
  last_updated TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS withdrawals (
  id TEXT PRIMARY KEY,
  shop_address TEXT,
  employee_name TEXT,
  employee_id TEXT,
  type TEXT,
  total_amount NUMERIC,
  expenses JSONB DEFAULT '[]',
  admin_name TEXT,
  confirmed BOOLEAN DEFAULT false,
  category TEXT,
  transfer_direction TEXT,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_withdrawals_shop ON withdrawals(shop_address);

CREATE TABLE IF NOT EXISTS loyalty_gamification (
  client_phone TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fortune_wheel_results (
  id SERIAL PRIMARY KEY,
  client_phone TEXT,
  data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employee_registrations (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employee_ratings (
  id TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Готово. Таблицы: ~45
-- ============================================
