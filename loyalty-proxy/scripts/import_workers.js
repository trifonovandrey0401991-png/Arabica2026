const fs = require("fs");
const path = require("path");
const db = require("../utils/db");
const { writeJsonFile } = require("../utils/async_fs");

const EMPLOYEES_DIR = "/var/www/employees";
const REGISTRATIONS_DIR = "/var/www/employee-registrations";

function parsePassportLine(line) {
  if (!line || !line.trim()) return null;
  const result = { series: "", number: "", issuedBy: "", issueDate: "" };

  const seriesMatch = line.match(/[Сс]ерия\s*:?\s*(\d{4})/i);
  if (seriesMatch) result.series = seriesMatch[1];

  const numberMatch = line.match(/[Нн]омер\s*:?\s*(\d{6})/i);
  if (numberMatch) result.number = numberMatch[1];

  const issuedByMatch = line.match(/(?:[Вв]ыдан|[Пп]аспорт\s+[Вв]ыдан)\s*:?\s*(.+?)(?:\s*[Дд]ата|$)/i);
  if (issuedByMatch) result.issuedBy = issuedByMatch[1].trim().replace(/,\s*$/, "");

  const dateMatch = line.match(/[Дд]ата\s*(?:выдачи)?\s*:?\s*(\d{2}[.\-\/]\d{2}[.\-\/]\d{4})/i);
  if (dateMatch) result.issueDate = dateMatch[1];

  return result;
}

async function main() {
  const workers = JSON.parse(fs.readFileSync("/tmp/workers_import.json", "utf-8"));

  // Get existing Arabica employees by phone
  const existingEmps = await db.findAll("employees", {}, { limit: 10000 });
  const empByPhone = {};
  for (const emp of existingEmps) {
    const phone = (emp.phone || "").replace(/[^0-9]/g, "");
    empByPhone[phone] = emp;
  }

  // Deduplicate workers by phone (keep active over deleted)
  const uniqueWorkers = {};
  for (const w of workers) {
    const phone = w.phone;
    if (!uniqueWorkers[phone] || w.status === "active") {
      uniqueWorkers[phone] = w;
    }
  }

  console.log(`Unique workers to process: ${Object.keys(uniqueWorkers).length}`);
  console.log(`Existing Arabica employees: ${existingEmps.length}`);

  let stats = { matched: 0, created: 0, registrations: 0, errors: 0 };

  for (const [phone, w] of Object.entries(uniqueWorkers)) {
    try {
      const existing = empByPhone[phone];

      if (existing) {
        stats.matched++;
        console.log(`MATCH: ${w.fio} (${phone}) -> ${existing.name} (${existing.id})`);
      } else {
        // Create new employee
        const employeeId = `employee_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
        const empData = {
          id: employeeId,
          name: w.fio,
          phone: phone,
          position: "Сотрудник",
          department: "",
          email: "",
          isAdmin: false,
          isManager: false,
          employeeName: "",
          referralCode: null,
          preferredWorkDays: [],
          preferredShops: [],
          shiftPreferences: {}
        };

        // Save to JSON
        const jsonPath = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
        fs.writeFileSync(jsonPath, JSON.stringify(empData, null, 2));

        // Save to DB
        try {
          await db.upsert("employees", {
            id: employeeId,
            name: w.fio,
            phone: phone,
            position: "Сотрудник",
            is_admin: false,
            is_manager: false,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
          });
        } catch (dbErr) {
          console.log(`  DB employee warning: ${dbErr.message}`);
        }

        stats.created++;
        console.log(`CREATE: ${w.fio} (${phone}) -> ${employeeId} [${w.status}]`);

        // Small delay to ensure unique IDs
        await new Promise(r => setTimeout(r, 5));
      }

      // Create employee-registration with passport data
      const passport = parsePassportLine(w.passport_line);

      // Verified only if: active in bot AND already existed in Arabica
      const shouldVerify = w.status === "active" && !!existing;

      // Build photo URLs
      const photoBase = "/passport-photos";
      const photo1 = w.photos[0] ? `${photoBase}/${w.photos[0]}` : null;
      const photo2 = w.photos[1] ? `${photoBase}/${w.photos[1]}` : null;
      const photo3 = w.photos[2] ? `${photoBase}/${w.photos[2]}` : null;

      const regData = {
        phone: phone,
        fullName: w.fio,
        passportSeries: passport ? passport.series : "",
        passportNumber: passport ? passport.number : "",
        issuedBy: passport ? passport.issuedBy : "",
        issueDate: passport ? passport.issueDate : "",
        passportFrontPhotoUrl: photo1,
        passportRegistrationPhotoUrl: photo2,
        additionalPhotoUrl: photo3,
        isVerified: shouldVerify,
        verifiedAt: shouldVerify ? new Date().toISOString() : null,
        verifiedBy: shouldVerify ? "Импорт из бота" : null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      // Save registration JSON
      const regJsonPath = path.join(REGISTRATIONS_DIR, `${phone}.json`);
      fs.writeFileSync(regJsonPath, JSON.stringify(regData, null, 2));

      // Save to DB (table uses id TEXT PK + data JSONB)
      try {
        await db.query(
          `INSERT INTO employee_registrations (id, data, created_at, updated_at)
           VALUES ($1, $2::jsonb, NOW(), NOW())
           ON CONFLICT (id) DO UPDATE SET
             data = $2::jsonb,
             updated_at = NOW()`,
          [phone, JSON.stringify(regData)]
        );
      } catch (dbErr) {
        console.log(`  DB reg warning: ${dbErr.message}`);
      }

      stats.registrations++;

    } catch (err) {
      console.error(`ERROR: ${w.fio} (${phone}): ${err.message}`);
      stats.errors++;
    }
  }

  // Fix names
  console.log("\n--- Fixing names ---");

  // Гамаюнов: Васильевич -> Владимирович
  try {
    await db.query(
      "UPDATE employees SET name = $1, updated_at = NOW() WHERE phone = $2",
      ["Гамаюнов Ярослав Владимирович", "79881060965"]
    );
    // Update JSON
    const r1 = await db.query("SELECT id FROM employees WHERE phone = $1", ["79881060965"]);
    if (r1.length > 0) {
      const jsonPath = path.join(EMPLOYEES_DIR, `${r1[0].id}.json`);
      if (fs.existsSync(jsonPath)) {
        const data = JSON.parse(fs.readFileSync(jsonPath));
        data.name = "Гамаюнов Ярослав Владимирович";
        fs.writeFileSync(jsonPath, JSON.stringify(data, null, 2));
      }
      console.log("FIXED: Гамаюнов Ярослав Владимирович");
    }
  } catch (e) { console.log("Fix Гамаюнов error:", e.message); }

  // Окаров: Русланови -> Русланович
  try {
    await db.query(
      "UPDATE employees SET name = $1, updated_at = NOW() WHERE phone = $2",
      ["Окаров Владимир Русланович", "79322229949"]
    );
    const r2 = await db.query("SELECT id FROM employees WHERE phone = $1", ["79322229949"]);
    if (r2.length > 0) {
      const jsonPath = path.join(EMPLOYEES_DIR, `${r2[0].id}.json`);
      if (fs.existsSync(jsonPath)) {
        const data = JSON.parse(fs.readFileSync(jsonPath));
        data.name = "Окаров Владимир Русланович";
        fs.writeFileSync(jsonPath, JSON.stringify(data, null, 2));
      }
      console.log("FIXED: Окаров Владимир Русланович");
    }
  } catch (e) { console.log("Fix Окаров error:", e.message); }

  console.log("\n=== ИТОГО ===");
  console.log(`Совпавших (добавлены паспорта): ${stats.matched}`);
  console.log(`Создано новых сотрудников: ${stats.created}`);
  console.log(`Паспортных записей создано: ${stats.registrations}`);
  console.log(`Ошибок: ${stats.errors}`);

  process.exit(0);
}

main().catch(err => { console.error("FATAL:", err); process.exit(1); });
