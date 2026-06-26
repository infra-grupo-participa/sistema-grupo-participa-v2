// Extração do ID da pasta do Google Drive — porta de dep_job_extract_folder_id.
export function extractDriveFolderId(input: string): string {
  const raw = String(input ?? '').trim();
  if (!raw) return '';
  if (/^[A-Za-z0-9_-]{10,}$/.test(raw)) return raw;
  const patterns = [
    /(?:^|\/)folders\/([A-Za-z0-9_-]{10,})/,
    /drive\/folders\/([A-Za-z0-9_-]{10,})/,
    /[?&]id=([A-Za-z0-9_-]{10,})/,
    /open\?id=([A-Za-z0-9_-]{10,})/,
  ];
  for (const p of patterns) {
    const m = raw.match(p);
    if (m?.[1]) return m[1];
  }
  return '';
}
