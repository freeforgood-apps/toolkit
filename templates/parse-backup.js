// Returns clean data or throws an error with a friendly message. Nothing is saved here.
const MAX_BACKUP_CHARS = 5_000_000;
const BLOCKED_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

function parseBackup(text, { appId, dataVersion, isValid }) {
  if (typeof text !== 'string' || !text.trim()) throw new Error('That backup is empty.');
  if (text.length > MAX_BACKUP_CHARS) throw new Error('That backup is too big to be from this app.');
  let data;
  try {
    data = JSON.parse(text, (key, value) => (BLOCKED_KEYS.has(key) ? undefined : value));
  } catch {
    throw new Error("That doesn't look like a backup from this app.");
  }
  if (!data || typeof data !== 'object' || data.app !== appId) {
    throw new Error('That backup is from a different app.');
  }
  if (!Number.isInteger(data.v) || data.v < 1) throw new Error('That backup looks damaged, so nothing was changed.');
  if (data.v > dataVersion) throw new Error('This backup is from a newer version. Update the app, then try again.');
  if (!isValid(data)) throw new Error('That backup looks damaged, so nothing was changed.');
  return data; // still run migrations, then show the confirm step before saving
}
