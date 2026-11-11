/**
 * Adherence streak = number of days in a row, ending YESTERDAY, on which the
 * user took every scheduled dose. Days with nothing scheduled are skipped
 * (they neither break nor extend the streak). Today is added by the app,
 * so the streak still updates while the phone is offline.
 */

const LOOKBACK_DAYS = 120;

/** "2026-11-11" for the given instant, in the given IANA timezone. */
export function localDate(instant, timeZone) {
  // en-CA formats dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(instant);
}

function addDays(isoDate, days) {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Mon = 1, Tue = 2, Wed = 4 … Sun = 64 — same bits as medication_schedules.days_mask. */
function weekdayBit(isoDate) {
  const jsDay = new Date(`${isoDate}T00:00:00Z`).getUTCDay(); // Sun = 0
  return 1 << ((jsDay + 6) % 7);
}

export async function computeStreak(db, userId, timeZone, now = new Date()) {
  const today = localDate(now, timeZone);
  const from = addDays(today, -LOOKBACK_DAYS);

  const { rows: schedules } = await db.query(
    `SELECT s.id, s.days_mask, m.start_date, m.end_date
     FROM medication_schedules s
     JOIN user_medications m ON m.id = s.user_medication_id
     WHERE m.user_id = $1 AND m.deleted_at IS NULL AND m.is_active
       AND s.deleted_at IS NULL`,
    [userId],
  );

  const { rows: taken } = await db.query(
    `SELECT schedule_id, scheduled_at FROM dose_logs
     WHERE user_id = $1 AND status = 'taken' AND deleted_at IS NULL
       AND scheduled_at >= ($2::date - 1)`,
    [userId, from],
  );
  const takenSet = new Set(
    taken.map((t) => `${t.schedule_id}|${localDate(t.scheduled_at, timeZone)}`),
  );

  let current = 0;
  let run = 0;
  let best = 0;
  let currentFinished = false;

  // Walk backwards from yesterday.
  for (let i = 1; i <= LOOKBACK_DAYS; i++) {
    const day = addDays(today, -i);
    const bit = weekdayBit(day);
    const due = schedules.filter(
      (s) => (s.days_mask & bit) !== 0 && s.start_date <= day && (!s.end_date || s.end_date >= day),
    );
    if (due.length === 0) continue;

    const allTaken = due.every((s) => takenSet.has(`${s.id}|${day}`));
    if (allTaken) {
      run += 1;
      if (!currentFinished) current = run;
    } else {
      currentFinished = true;
      best = Math.max(best, run);
      run = 0;
    }
  }
  best = Math.max(best, run, current);

  return { daysBeforeToday: current, best, asOf: today };
}
