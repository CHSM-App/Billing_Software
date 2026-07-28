/// Unicode Devanagari  →  ISCII (IS 13194:1991) single-byte encoder.
///
/// WHY
/// ---
/// Many Indian thermal printers (incl. the Shreyans 80B) ship with a built-in
/// Devanagari font ROM. They render Marathi/Hindi as fast and crisp as English
/// — but ONLY when text is sent as ISCII single-byte codes on the printer's
/// Devanagari code page, NOT as UTF-8 and NOT as a raster image.
///
/// This is exactly what the "random Play Store app" that works on your printer
/// is doing: Unicode → ISCII bytes → select Devanagari code page → print text.
///
/// KEY FACT that makes this simple: ISCII stores text in the SAME logical order
/// as Unicode Devanagari (consonant, then matra; conjunct = consonant + halant +
/// consonant). So the conversion is a near 1:1 codepoint→byte mapping. No
/// visual reordering is required — the printer's font engine does the shaping.
class IsciiEncoder {
  /// Unicode codepoint (U+0900 block) → ISCII byte. Built from IS 13194:1991.
  static const Map<int, int> _map = {
    // Vowel modifiers
    0x0901: 0xA1, // ँ chandrabindu
    0x0902: 0xA2, // ं anusvara
    0x0903: 0xA3, // ः visarga

    // Independent vowels
    0x0905: 0xA4, // अ
    0x0906: 0xA5, // आ
    0x0907: 0xA6, // इ
    0x0908: 0xA7, // ई
    0x0909: 0xA8, // उ
    0x090A: 0xA9, // ऊ
    0x090B: 0xAA, // ऋ
    0x090E: 0xAB, // ऎ
    0x090F: 0xAC, // ए
    0x0910: 0xAD, // ऐ
    0x090D: 0xAE, // ऍ
    0x0912: 0xAF, // ऒ
    0x0913: 0xB0, // ओ
    0x0914: 0xB1, // औ
    0x0911: 0xB2, // ऑ

    // Consonants
    0x0915: 0xB3, // क
    0x0916: 0xB4, // ख
    0x0917: 0xB5, // ग
    0x0918: 0xB6, // घ
    0x0919: 0xB7, // ङ
    0x091A: 0xB8, // च
    0x091B: 0xB9, // छ
    0x091C: 0xBA, // ज
    0x091D: 0xBB, // झ
    0x091E: 0xBC, // ञ
    0x091F: 0xBD, // ट
    0x0920: 0xBE, // ठ
    0x0921: 0xBF, // ड
    0x0922: 0xC0, // ढ
    0x0923: 0xC1, // ण
    0x0924: 0xC2, // त
    0x0925: 0xC3, // थ
    0x0926: 0xC4, // द
    0x0927: 0xC5, // ध
    0x0928: 0xC6, // न
    0x0929: 0xC7, // ऩ
    0x092A: 0xC8, // प
    0x092B: 0xC9, // फ
    0x092C: 0xCA, // ब
    0x092D: 0xCB, // भ
    0x092E: 0xCC, // म
    0x092F: 0xCD, // य
    0x095F: 0xCE, // य़
    0x0930: 0xCF, // र
    0x0931: 0xD0, // ऱ
    0x0932: 0xD1, // ल
    0x0933: 0xD2, // ळ
    0x0934: 0xD3, // ऴ
    0x0935: 0xD4, // व
    0x0936: 0xD5, // श
    0x0937: 0xD6, // ष
    0x0938: 0xD7, // स
    0x0939: 0xD8, // ह

    // Matras (dependent vowel signs)
    0x093E: 0xDA, // ा
    0x093F: 0xDB, // ि
    0x0940: 0xDC, // ी
    0x0941: 0xDD, // ु
    0x0942: 0xDE, // ू
    0x0943: 0xDF, // ृ
    0x0946: 0xE0, // ॆ
    0x0947: 0xE1, // े
    0x0948: 0xE2, // ै
    0x0945: 0xE3, // ॅ
    0x094A: 0xE4, // ॊ
    0x094B: 0xE5, // ो
    0x094C: 0xE6, // ौ
    0x0949: 0xE7, // ॉ

    // Special
    0x094D: 0xE8, // ् halant / virama (conjunct joiner)
    0x093C: 0xE9, // ़ nukta
    0x0964: 0xEA, // । danda

    // Devanagari digits (some printers render these; ASCII 0-9 also fine)
    0x0966: 0xF1, // ०
    0x0967: 0xF2, // १
    0x0968: 0xF3, // २
    0x0969: 0xF4, // ३
    0x096A: 0xF5, // ४
    0x096B: 0xF6, // ५
    0x096C: 0xF7, // ६
    0x096D: 0xF8, // ७
    0x096E: 0xF9, // ८
    0x096F: 0xFA, // ९
  };

  /// Precomposed Devanagari letters (nukta forms) that Unicode encodes as a
  /// single codepoint but ISCII expresses as base consonant + nukta (0xE9).
  static const Map<int, List<int>> _nuktaDecomp = {
    0x0958: [0xB3, 0xE9], // क़ = क + nukta
    0x0959: [0xB4, 0xE9], // ख़
    0x095A: [0xB5, 0xE9], // ग़
    0x095B: [0xBA, 0xE9], // ज़
    0x095C: [0xBF, 0xE9], // ड़
    0x095D: [0xC0, 0xE9], // ढ़
    0x095E: [0xC9, 0xE9], // फ़
  };

  /// True if the char is in the Devanagari Unicode block (or a joiner we drop).
  static bool isDevanagari(int cp) =>
      (cp >= 0x0900 && cp <= 0x097F);

  /// True if [s] contains any Devanagari character.
  static bool containsDevanagari(String s) =>
      s.runes.any(isDevanagari);

  /// Convert a string to ISCII bytes.
  ///
  /// - Devanagari codepoints → their ISCII byte(s).
  /// - ASCII (< 0x80) passes through unchanged (English/numbers/punctuation).
  /// - ZWJ/ZWNJ (U+200C/U+200D) are dropped — ISCII conjuncts are formed purely
  ///   by consonant + halant + consonant, which is already in the stream.
  /// - Anything else (unmappable) → [fallback] (default '?').
  static List<int> encode(String s, {int fallback = 0x3F}) {
    final out = <int>[];
    for (final cp in s.runes) {
      if (cp == 0x200C || cp == 0x200D) continue; // ZWNJ / ZWJ
      if (cp < 0x80) {
        out.add(cp); // plain ASCII
        continue;
      }
      final direct = _map[cp];
      if (direct != null) {
        out.add(direct);
        continue;
      }
      final nukta = _nuktaDecomp[cp];
      if (nukta != null) {
        out.addAll(nukta);
        continue;
      }
      // Common non-ASCII punctuation we can approximate:
      switch (cp) {
        case 0x2018: // ‘
        case 0x2019: // ’
          out.add(0x27); // '
          break;
        case 0x201C: // “
        case 0x201D: // ”
          out.add(0x22); // "
          break;
        case 0x2013: // –
        case 0x2014: // —
          out.add(0x2D); // -
          break;
        default:
          out.add(fallback);
      }
    }
    return out;
  }
}
