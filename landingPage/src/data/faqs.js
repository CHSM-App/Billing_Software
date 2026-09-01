/**
 * FAQ copy, kept in a plain .js module (no JSX) so both the React section and
 * prerender.js — which runs in bare Node and cannot parse JSX — can import it.
 * That way the answers a visitor reads and the FAQPage schema Google indexes
 * can never drift apart.
 */
export const FAQS = [
  {
    q: 'Does Vittam work without an internet connection?',
    a: 'Yes. Vittam is offline-first — billing, inventory lookups and printing all keep working when the connection drops. Every bill is stored on the device and syncs to the cloud automatically the moment you are back online, so nothing is lost during a power cut or network outage.',
  },
  {
    q: 'Is Vittam GST-ready for Indian businesses?',
    a: 'Yes. You can set GST rates per item, capture your GSTIN and business details, and generate GST-compliant invoices. Reports break down tax collected so filing returns is straightforward.',
  },
  {
    q: 'What kinds of businesses is this billing software for?',
    a: 'Vittam is built for Indian small businesses — kirana and general stores, small supermarkets, cafes and QSRs, and restaurants that need table-wise billing. Retail counters get fast barcode-ready billing; restaurants get per-table orders and split bills.',
  },
  {
    q: 'How much does Vittam cost?',
    a: 'Vittam is free for your first month — full features, no card needed to start. After the trial you move to a paid plan to keep using it. Your data stays yours and nothing is deleted while you decide. For current pricing, message us on WhatsApp at +91 94222 29951 and we will share the plan that fits your shop size.',
  },
  {
    q: 'Can I print bills on a thermal printer?',
    a: 'Yes. Connect a standard thermal receipt printer and Vittam prints a professional receipt on every bill. You can also send the same bill to a customer over WhatsApp instead of printing it, which saves paper and gives them a permanent copy.',
  },
  {
    q: 'Can my staff use it without seeing my business reports?',
    a: 'Yes. Add cashiers and assign roles from the owner account. Staff can bill and manage orders while revenue, expense and analytics screens stay restricted to the owner.',
  },
  {
    q: 'Which devices does Vittam run on?',
    a: 'Vittam runs on Windows PCs and Android phones and tablets. The Windows build is a direct download and the Android app is on the Google Play Store. Your data stays in sync across every device signed in to the same business.',
  },
  {
    q: 'Can I track expenses and see how the shop is performing?',
    a: 'Yes. Log one-off and recurring expenses by category, then review daily revenue breakdowns, payment-mode splits and expense summaries in the reports section to see exactly where your money is going.',
  },
]
