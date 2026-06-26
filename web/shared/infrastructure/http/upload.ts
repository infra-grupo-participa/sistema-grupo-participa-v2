// Validação rigorosa de upload — porta de api_validate_uploaded_file (magic bytes).

export const PLACA_MIME_MAP: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export interface ValidatedUpload {
  buffer: Buffer;
  mime: string;
  ext: string;
  size: number;
}

function sniffMime(bytes: Buffer): string | null {
  if (bytes.length >= 5 && bytes.subarray(0, 5).toString('latin1') === '%PDF-') return 'application/pdf';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  )
    return 'image/png';
  if (
    bytes.length >= 12 &&
    bytes.subarray(0, 4).toString('latin1') === 'RIFF' &&
    bytes.subarray(8, 12).toString('latin1') === 'WEBP'
  )
    return 'image/webp';
  return null;
}

/** Valida um File de FormData; retorna o conteúdo validado ou null. */
export async function validateUpload(
  file: File | null,
  mimeMap: Record<string, string>,
  maxBytes: number,
): Promise<ValidatedUpload | null> {
  if (!file || typeof file.arrayBuffer !== 'function') return null;
  const size = file.size;
  if (size < 1 || size > maxBytes) return null;
  const buffer = Buffer.from(await file.arrayBuffer());
  const mime = sniffMime(buffer);
  if (!mime || !mimeMap[mime]) return null;
  return { buffer, mime, ext: mimeMap[mime], size };
}
