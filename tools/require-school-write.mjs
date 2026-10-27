export function requireSchoolWrite() {
  if (!process.argv.includes('--allow-school-writes')) {
    throw new Error('Real school write disabled. Explicit --allow-school-writes is required.');
  }
}
