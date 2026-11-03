const crypto = require('crypto');

// Base URL used in receipt links — no trailing slash
const RECEIPT_BASE = process.env.RECEIPT_BASE_URL || 'https://Vittam.vengurlatech.com';

// Public receipt link token (/receipt/<token>, /receipt/s/<token>).
function generateReceiptToken() {
  // 16 alphanumeric chars (base62) — ~95 bits of entropy, unguessable.
  // Deliberately avoids base64url's '-' and '_': some WhatsApp/link renderers
  // munge those (e.g. inserting a space before a leading '-'), producing a
  // broken receipt URL. Pure [A-Za-z0-9] survives every renderer intact.
  const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.randomBytes(16);
  let out = '';
  for (let i = 0; i < 16; i++) out += ALPHABET[bytes[i] % 62];
  return out;
}

module.exports = { generateReceiptToken, RECEIPT_BASE };
