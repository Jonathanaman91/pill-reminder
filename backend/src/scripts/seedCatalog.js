// npm run catalog:seed — adds a starter set of common medications to the
// global medication database, so the admin panel is not empty on first use.
// Safe to run again: entries that already exist are skipped.
import { pool } from '../db.js';

// [generic name, brand name, form, strength, unit, description]
const STARTER = [
  ['Paracetamol', 'Panadol', 'tablet', 500, 'mg', 'Relieves pain and lowers fever.'],
  ['Ibuprofen', 'Nurofen', 'tablet', 200, 'mg', 'Relieves pain, swelling and fever.'],
  ['Metformin', 'Glucophage', 'tablet', 500, 'mg', 'Lowers blood sugar in type 2 diabetes.'],
  ['Gliclazide', 'Diamicron MR', 'tablet', 30, 'mg', 'Lowers blood sugar in type 2 diabetes.'],
  ['Amlodipine', 'Norvasc', 'tablet', 5, 'mg', 'Lowers high blood pressure.'],
  ['Perindopril', 'Coversyl', 'tablet', 4, 'mg', 'Lowers high blood pressure.'],
  ['Losartan', 'Cozaar', 'tablet', 50, 'mg', 'Lowers high blood pressure.'],
  ['Atorvastatin', 'Lipitor', 'tablet', 20, 'mg', 'Lowers cholesterol.'],
  ['Simvastatin', 'Zocor', 'tablet', 20, 'mg', 'Lowers cholesterol.'],
  ['Omeprazole', 'Losec', 'capsule', 20, 'mg', 'Reduces stomach acid.'],
  ['Amoxicillin', 'Amoxil', 'capsule', 500, 'mg', 'Antibiotic for bacterial infections.'],
  ['Cetirizine', 'Zyrtec', 'tablet', 10, 'mg', 'Relieves allergy symptoms.'],
  ['Loratadine', 'Clarityne', 'tablet', 10, 'mg', 'Relieves allergy symptoms.'],
  ['Salbutamol', 'Ventolin', 'inhaler', 100, 'mcg', 'Reliever inhaler for asthma.'],
  ['Levothyroxine', 'Euthyrox', 'tablet', 50, 'mcg', 'Replaces thyroid hormone.'],
];

try {
  let added = 0;
  for (const [generic, brand, form, strength, unit, description] of STARTER) {
    const { rowCount } = await pool.query(
      `INSERT INTO medication_catalog (generic_name, brand_name, form, strength, strength_unit, description)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (generic_name, brand_name, form, strength, strength_unit) DO NOTHING`,
      [generic, brand, form, strength, unit, description],
    );
    added += rowCount;
  }
  console.log(`Catalog ready: ${added} added, ${STARTER.length - added} already there.`);
} catch (err) {
  console.error(`Seeding failed: ${err.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
