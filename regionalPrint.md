# Printing Regional Languages on Thermal Printers

A simple guide to printing Indian (or any non-Latin) languages — Marathi, Hindi,
Tamil, Gujarati, Bengali, etc. — on cheap Bluetooth/USB ESC/POS thermal
printers.

---

## The core problem

Most cheap thermal printers (80mm / 58mm ESC/POS clones) can print **only the
languages built into their font ROM**. Print the printer's self-test page and
look at the "Font" section — you will usually see something like:

```
FontInfo:
  ASCII       12x24, 8x16
  GBK         24x24     (Chinese)
  BIG5        24x24     (Chinese)
  SHIFT-JIS   24x24     (Japanese)
```

If you don't see your script (Devanagari, Tamil, …) listed, **the printer
physically cannot print it as text.** Sending Marathi bytes will produce
`?????`, boxes `□□□`, or random symbols.

Complex Indian scripts also need *shaping* — joining half-letters, placing matras
(ा ि ी), and forming conjuncts like क्ष, त्र, ज्ञ. A simple code page cannot do
this even if the glyphs existed. This is why "just pick the right encoding"
never works for these scripts.

---

## The solution: print text as an image (raster)

Since the printer can't render the script, you render it yourself into a
**black-and-white picture**, then send that picture as dots. Every ESC/POS
printer can print raw dots. This is exactly what professional POS apps do.

The pipeline:

```
"कॉफी"  →  render to pixels (with a real font)  →  black/white bitmap
        →  ESC/POS raster command  →  printer prints the dots
```

You keep working with normal text strings; only the *rendering* changes.

---

## Step 1 — Bundle a font that covers your script

Do **not** rely on the phone/OS font — it may be missing or differ per device.
Ship the font with your app. Google's **Noto** fonts cover every Indian script:

- Devanagari (Hindi/Marathi): `NotoSansDevanagari`
- Tamil: `NotoSansTamil`
- Gujarati: `NotoSansGujarati`
- …and so on.

Each script needs its own font file. In Flutter, register it in `pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: NotoSansDevanagari
      fonts:
        - asset: assets/fonts/NotoSansDevanagari-Regular.ttf
```

---

## Step 2 — Render the text to an image

Use the platform's text engine (it does the shaping for you — matras, conjuncts,
everything). In Flutter, `dart:ui` uses HarfBuzz under the hood:

```dart
Future<ui.Image> renderText(String text, {int widthDots = 576}) async {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontFamily: 'NotoSansDevanagari',
    fontSize: 26,
  ))..addText(text);

  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: widthDots.toDouble()));

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src); // white bg
  canvas.drawParagraph(paragraph, Offset.zero);

  return recorder.endRecording()
      .toImage(widthDots, paragraph.height.ceil());
}
```

**Tip for sharp text:** render at 2× size and scale it back down before
converting to 1-bit. Thin strokes survive much better this way.

---

## Step 3 — Convert the image to 1-bit dots

A thermal printer dot is either on (black) or off (white). Compare each pixel's
brightness to a threshold:

```dart
// width MUST be padded to a multiple of 8 — see the warning below.
final bytesPerRow = (width + 7) ~/ 8;
final packed = Uint8List(bytesPerRow * height);

for (var y = 0; y < height; y++) {
  for (var x = 0; x < width; x++) {
    final lum = luminanceOfPixel(x, y);   // 0 = black .. 255 = white
    if (lum < 128) {                      // dark enough → a dot
      packed[y * bytesPerRow + (x >> 3)] |= (0x80 >> (x & 7));
    }
  }
}
```

> ⚠️ **The #1 bug: width must be a multiple of 8.**
> ESC/POS packs 8 horizontal dots into 1 byte. If your image width isn't a
> multiple of 8, the row length and the command's width field disagree, and
> **every row shifts a little → the whole print comes out sheared diagonally.**
> Pad the image width up to the next multiple of 8 (`(w + 7) & ~7`) with white.

For **text**, use a plain threshold (128), **not** dithering — dithering fuzzes
thin strokes on a thermal head.

---

## Step 4 — Send it with the GS v 0 raster command

`GS v 0` is the standard "print raster bitmap" command:

```
1D 76 30 m  xL xH  yL yH  [image data]
```

- `m = 0` (normal size)
- `xL xH` = bytesPerRow as a little-endian 16-bit number
- `yL yH` = height in dots as a little-endian 16-bit number

```dart
List<int> gsv0(Uint8List packed, int bytesPerRow, int height) {
  return [
    0x1D, 0x76, 0x30, 0x00,
    bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
    height & 0xFF, (height >> 8) & 0xFF,
    ...packed,
  ];
}
```

**Band tall images.** Cheap printers have small buffers. Split a tall receipt
into horizontal bands (~200–300 dots each), sending one complete `GS v 0`
command per band, back-to-back. This prints smoothly instead of stuttering.

---

## Step 5 — Send over Bluetooth quickly

Send the bytes in **large chunks with little/no delay** — this is what makes it
print as fast as English text. Only if you see blank bands or corruption
partway down (dropped bytes) should you reduce the chunk size and add a small
delay (start ~20 ms) between chunks, then use the smallest delay that stays
clean. Don't default to a big blanket delay.

```dart
// Pseudo: one write is usually fastest and cleanest.
await bluetooth.writeBytes(payload);
// If bytes drop, fall back to chunks:
// for each 1024-byte chunk: write; wait 20ms;
```

> ⚠️ Some plugins expect a plain `List<int>`. Passing a `Uint8List` can cross the
> native bridge as a `byte[]` and crash (`byte[] cannot be cast to List`).
> Convert with `List<int>.from(chunk)` if you hit this.

---

## Keeping columns aligned (receipts)

For English you align columns by padding with spaces (monospace). **That does
NOT work for regional scripts** — the glyphs are proportional (variable width),
so space-padding overflows and the price wraps to the next line.

Instead, lay out the image as a **real table**: give each column a fixed
fraction of the width and draw each cell at its own x-position with its own
alignment (name = left, amount = right).

```
| item name (46%) | qty (14%) | price (20%) | total (20%) |
```

---

## When to use text vs image

You don't have to rasterize everything. A good rule:

```dart
bool needsImage(String receipt) =>
    receipt.runes.any((c) => c > 127); // any non-ASCII char?

if (needsImage(text)) {
  printAsRaster(text);   // regional language → image
} else {
  printAsPlainText(text); // pure English/numbers → fast native text
}
```

English/number-only receipts stay fast; only receipts containing regional text
take the image path.

---

## Quick checklist

- [ ] Bundle a Noto font for each script (don't rely on the system font).
- [ ] Render text with the platform text engine (it shapes matras/conjuncts).
- [ ] Render at 2× then downscale for crisp strokes.
- [ ] **Pad image width to a multiple of 8** (prevents diagonal shear).
- [ ] Threshold at 128 for text; no dithering.
- [ ] Send with `GS v 0`, banded into ~256-dot chunks.
- [ ] One big Bluetooth write; add small delay only if bytes drop.
- [ ] For tables, use fixed fractional columns, not space padding.
- [ ] Rasterize only when the text contains non-ASCII characters.

---

## Why not just "use the right encoding / code page"?

Because the glyphs and the shaping engine don't exist in the printer. Code pages
(ISCII, UTF-8, etc.) only pick among fonts the printer already has. If the ROM
has no Devanagari/Tamil font — which is true for almost all cheap clones — no
encoding can help. Image printing is the reliable, universal answer, and it
works for **any** language a font can render.
