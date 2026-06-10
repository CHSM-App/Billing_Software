import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import {
  ArrowLeft, Search, Receipt, Package, Coffee, BarChart2,
  WifiOff, Printer, Users, Settings, MessageCircle,
  ChevronDown, ChevronUp, HelpCircle, Mail, IndianRupee,
} from 'lucide-react'

/* ── Data ───────────────────────────────────────────── */

const CATEGORIES = [
  { icon: <Receipt size={20} />,      label: 'Billing',           id: 'billing' },
  { icon: <Package size={20} />,      label: 'Items & Inventory', id: 'items' },
  { icon: <Coffee size={20} />,       label: 'Table Billing',     id: 'tables' },
  { icon: <BarChart2 size={20} />,    label: 'Reports',           id: 'reports' },
  { icon: <IndianRupee size={20} />,  label: 'Expenses',          id: 'expenses' },
  { icon: <WifiOff size={20} />,      label: 'Offline Mode',      id: 'offline' },
  { icon: <Printer size={20} />,      label: 'Printing',          id: 'printing' },
  { icon: <Users size={20} />,        label: 'Staff & Roles',     id: 'staff' },
  { icon: <Settings size={20} />,     label: 'Settings',          id: 'settings' },
  { icon: <MessageCircle size={20} />,label: 'WhatsApp',          id: 'whatsapp' },
]

const FAQS = [
  // ── Billing ─────────────────────────────────────────────────────────────
  {
    category: 'billing',
    q: 'How do I create a new bill?',
    a: 'Open the Billing screen from the left sidebar. Tap the + button next to any item to add it to your order. Adjust quantities with the − and + controls. Once all items are added, tap "Generate Bill" on the right panel. Select the payment mode (Cash, UPI, or Card) before generating.',
  },
  {
    category: 'billing',
    q: 'Can I add a customer name to a bill?',
    a: 'Yes. On the billing screen, expand the "Customer Details (Optional)" section in the order panel before generating the bill. Enter the customer\'s name and phone number. This information appears on the generated receipt and is stored in the bill record.',
  },
  {
    category: 'billing',
    q: 'How do I apply a discount on a bill?',
    a: 'On the order panel, tap the discount icon (%) near the total. You can enter a flat rupee amount or a percentage discount. The discount is applied to the bill total before generation and is shown separately on the receipt.',
  },
  {
    category: 'billing',
    q: 'Can I edit or cancel a bill after it is generated?',
    a: 'Bills cannot be edited after generation to maintain accurate records. However, you can void a bill from the Bill History screen. Open the bill, tap the three-dot menu in the top right, and select "Void Bill". A voided bill is marked as cancelled and excluded from reports.',
  },
  {
    category: 'billing',
    q: 'How do I search for an item quickly during billing?',
    a: 'Use the search bar at the top of the billing screen. Start typing the item name and matching results appear instantly. You can also filter by category using the category tabs below the search bar, or scan the item\'s barcode to add it directly.',
  },
  {
    category: 'billing',
    q: 'Does Vittam support GST billing?',
    a: 'Yes. Vittam is GST-ready. You can add your GSTIN in Settings → Business Profile. GST rates can be assigned per item (0%, 5%, 12%, 18%, 28%). The GST breakdown — CGST, SGST, or IGST — is shown separately on the bill and included in exports.',
  },
  {
    category: 'billing',
    q: 'Can I view my bill history?',
    a: 'Yes. Open the Bill History screen from the sidebar. You can browse all past bills, filter by date range, payment mode, or staff member. Tap any bill to see the full details including items, taxes, discounts, and customer info.',
  },

  // ── Items & Inventory ────────────────────────────────────────────────────
  {
    category: 'items',
    q: 'How do I add a new item to my inventory?',
    a: 'Go to Items from the sidebar. Tap the "+ Add Item" button at the bottom right. Fill in the item name, price, category, and GST rate. Optionally add a barcode or SKU. Tap Save — the item appears on the billing screen immediately.',
  },
  {
    category: 'items',
    q: 'How do I assign a barcode to an item?',
    a: 'When adding or editing an item, tap the barcode icon in the barcode field. This opens your device camera for scanning. Point it at the product barcode and it will be captured automatically. You can also type the barcode number manually if camera scanning is not available.',
  },
  {
    category: 'items',
    q: 'Can I create custom categories?',
    a: 'Yes. When adding or editing an item, tap the category field and select "Add New Category" from the dropdown. Enter your category name and it will be saved for all future items. Categories also appear as filter tabs on the billing screen.',
  },
  {
    category: 'items',
    q: 'How do I bulk import items?',
    a: 'From the Items screen, tap the menu icon (⋮) at the top right and select "Import Items". Download the CSV template, fill in your items (name, price, category, GST rate, barcode), and upload the file. All valid rows are imported at once. Do not include the ₹ symbol in price fields.',
  },
  {
    category: 'items',
    q: 'How do I delete an item?',
    a: 'On the Items screen, tap the red trash icon next to the item you want to delete. Confirm the deletion when prompted. Deleting an item does not remove it from past bills — historical bill records are always preserved.',
  },
  {
    category: 'items',
    q: 'Can I set different prices for the same item?',
    a: 'You can create separate item entries for different variants or pack sizes (e.g. "Cold Drink 250ml" and "Cold Drink 500ml") each with their own price. Variant-level pricing within a single item entry is not currently supported.',
  },

  // ── Table Billing ────────────────────────────────────────────────────────
  {
    category: 'tables',
    q: 'How do I set up tables for my restaurant?',
    a: 'Go to Settings → Business Profile → Table Setup. Add the number of tables or sections your restaurant has and name them (e.g. "Table 1", "A1", "Terrace 3"). Once saved, tables appear on the Billing screen when Vittam is in Restaurant mode.',
  },
  {
    category: 'tables',
    q: 'Can I merge or split a table bill?',
    a: 'To split a table bill, open the active table order and tap "Split Bill". You can split by specific items or by equal division among customers. To merge two open table orders, select both tables from the table view and tap "Merge Orders".',
  },
  {
    category: 'tables',
    q: 'What happens if I close the app mid-order?',
    a: 'All open table orders are saved automatically. When you reopen Vittam, every active table order will be exactly as you left it — even if the device was offline. No order data is lost on app restart or device reboot.',
  },
  {
    category: 'tables',
    q: 'How do I switch between Counter mode and Restaurant mode?',
    a: 'Go to Settings → Business Profile and change your Business Type. Select "Restaurant / Cafe" for table billing mode or "Retail / Shop" for standard counter billing. The billing screen adapts to show the appropriate interface.',
  },

  // ── Reports ──────────────────────────────────────────────────────────────
  {
    category: 'reports',
    q: "How do I view today's sales?",
    a: 'Open the Reports section from the sidebar. The default view shows the current month. Tap "Today" to filter to just today\'s data. You will see total revenue, number of bills, average bill value, and a breakdown by payment mode (Cash, UPI, Card).',
  },
  {
    category: 'reports',
    q: 'Can I export reports to a spreadsheet?',
    a: 'Yes. From the Reports screen, tap the export icon in the top right corner. You can export the selected date range as CSV or PDF. The export includes bill-level detail, item-wise sales summary, GST summary, and expense data.',
  },
  {
    category: 'reports',
    q: 'What does the item-wise sales report show?',
    a: 'The item-wise report shows total quantity sold, revenue generated, and GST collected for each item within the selected date range. It helps you identify your best-selling products and category-level revenue contribution.',
  },
  {
    category: 'reports',
    q: 'Can I see a profit summary in reports?',
    a: 'The Reports screen shows net revenue after subtracting logged expenses. If you record your expenses regularly in the Expenses section, the report will display both gross revenue and approximate net revenue for the selected period.',
  },

  // ── Expenses ─────────────────────────────────────────────────────────────
  {
    category: 'expenses',
    q: 'How do I log an expense?',
    a: 'Open the Expenses section from the sidebar and tap "+ Add Expense". Enter the category (e.g. Rent, Electricity, Supplies), amount, date, and an optional note. The expense is saved and deducted from revenue in your monthly report.',
  },
  {
    category: 'expenses',
    q: 'Can I set up recurring expenses?',
    a: 'Yes. When adding an expense, toggle "Recurring" and set the frequency (monthly, weekly). Vittam will automatically log this expense on the scheduled date each period so you do not have to enter it manually every time.',
  },
  {
    category: 'expenses',
    q: 'Can I categorise my expenses?',
    a: 'Yes. Common expense categories like Rent, Electricity, Salaries, Supplies, and Maintenance are available by default. You can also add custom categories to match your business needs.',
  },

  // ── Offline Mode ─────────────────────────────────────────────────────────
  {
    category: 'offline',
    q: 'Does Vittam work without an internet connection?',
    a: 'Yes. Vittam is built offline-first. You can create bills, add items, manage inventory, and run your store with zero internet connectivity. All data is stored locally and synced to the cloud automatically when your connection is restored.',
  },
  {
    category: 'offline',
    q: 'How do I know which bills have not synced yet?',
    a: 'Go to Settings → Unsynced Bills to see all bills created offline that are pending sync. A sync indicator badge also appears on the Settings icon when there are unsynced records. Once online, sync runs automatically in the background without any action needed.',
  },
  {
    category: 'offline',
    q: 'Is my data safe if I uninstall the app?',
    a: 'All data that has been synced to the cloud is safe and will be fully restored when you reinstall and log in. Data created offline that was never synced may not be recoverable. We recommend ensuring your device is online and fully synced before uninstalling.',
  },

  // ── Printing ─────────────────────────────────────────────────────────────
  {
    category: 'printing',
    q: 'How do I connect a thermal printer?',
    a: 'Go to Settings → Printer Setup. Choose your connection type — Bluetooth or LAN/WiFi. For Bluetooth, pair your printer with the device first. For network printers, enter the printer\'s IP address. Tap "Test Print" to confirm the connection is working.',
  },
  {
    category: 'printing',
    q: 'Which thermal printer models are supported?',
    a: 'Vittam supports most ESC/POS compatible thermal printers including popular models from Epson, Star Micronics, TVS, and generic 58mm/80mm Bluetooth or USB printers. If your printer accepts ESC/POS commands, it will work with Vittam.',
  },
  {
    category: 'printing',
    q: 'Can I customise the receipt layout?',
    a: 'Yes. Go to Settings → Business Profile → Receipt Settings. You can add your store logo, business address, GSTIN, a custom footer message (e.g. "Thank you for visiting!"), and choose what to show on the receipt — item codes, GST breakdown, payment mode, and more.',
  },
  {
    category: 'printing',
    q: 'Can I print a duplicate copy of a past bill?',
    a: 'Yes. Open the Bill History screen, find the bill you want to reprint, tap it to open the details, and tap the Print icon. The bill will be sent to your connected printer exactly as it was originally generated.',
  },

  // ── Staff & Roles ────────────────────────────────────────────────────────
  {
    category: 'staff',
    q: 'How do I add a cashier to my store?',
    a: 'Go to Settings → Manage Staff → Add Staff Member. Enter the cashier\'s name, phone number, and a 4 or 6 digit PIN. The cashier can log in on any device using their phone number and PIN. Cashiers can access Billing and Items screens; owner-level screens (Reports, Expenses, Settings) are restricted.',
  },
  {
    category: 'staff',
    q: 'Can I see which bills a specific staff member generated?',
    a: 'Yes. In the Bill History screen, use the filter to select a specific staff member. Each bill record shows which account generated it. This is useful for end-of-shift reconciliation and accountability.',
  },
  {
    category: 'staff',
    q: 'How do I remove a staff member?',
    a: 'Go to Settings → Manage Staff, find the staff member, and tap "Remove". Their account is deactivated immediately and they can no longer log in. All bill history associated with their account is retained for your records.',
  },
  {
    category: 'staff',
    q: 'How many staff members can I add?',
    a: 'The number of staff accounts depends on your subscription plan. Vittam Free supports up to 2 staff members. Vittam Pro supports unlimited staff accounts. Visit Settings → Subscription to check or upgrade your current plan.',
  },

  // ── Settings ─────────────────────────────────────────────────────────────
  {
    category: 'settings',
    q: 'How do I update my business name or address?',
    a: 'Go to Settings → Business Profile. You can edit your business name, address, phone number, GSTIN, and business type. Changes take effect immediately and appear on all future bills and receipts.',
  },
  {
    category: 'settings',
    q: 'How do I change my account PIN?',
    a: 'Go to Settings, scroll to the Account section, and tap "Change PIN". Enter your current PIN first, then set a new 4 or 6 digit PIN. Keep your new PIN safe — it cannot be recovered without identity verification via your registered phone number.',
  },
  {
    category: 'settings',
    q: 'How do I delete my account?',
    a: 'Contact our support team at support@vengurlatech.com or reach out via WhatsApp to request account deletion. Once submitted, your account and all associated data will be permanently deleted within 30 days. This action cannot be undone.',
  },
  {
    category: 'settings',
    q: 'Can I use Vittam on multiple devices?',
    a: 'Yes. Log in with the same phone number and PIN on any device — Android, Windows PC, or the web app at app.Vittam.in. Data syncs across all devices automatically when you are online.',
  },

  // ── WhatsApp ─────────────────────────────────────────────────────────────
  {
    category: 'whatsapp',
    q: 'How do I send a bill via WhatsApp?',
    a: 'After generating a bill, tap the "Share" icon on the bill view screen and select "WhatsApp". Enter or confirm the customer\'s phone number. The bill is shared as a formatted message or PDF directly through WhatsApp — no printing needed.',
  },
  {
    category: 'whatsapp',
    q: 'Does the customer need to have WhatsApp?',
    a: 'Yes. WhatsApp sharing requires the customer to have WhatsApp installed on their phone. If they don\'t, you can print a physical receipt using your connected thermal printer instead.',
  },
  {
    category: 'whatsapp',
    q: 'Can I customise the WhatsApp message format?',
    a: 'The bill shared via WhatsApp includes your business name, bill number, itemised list, total amount, payment mode, and your footer message. The business name and footer can be customised in Settings → Business Profile → Receipt Settings.',
  },
]

/* ── Components ─────────────────────────────────────── */

function FAQItem({ q, a }) {
  const [open, setOpen] = useState(false)
  return (
    <div
      className="rounded-2xl overflow-hidden transition-all cursor-pointer"
      style={{
        background: '#fff',
        border: open ? '1.5px solid rgba(0,229,192,0.35)' : '1px solid rgba(0,0,0,0.07)',
      }}
      onClick={() => setOpen(!open)}
    >
      <div className="flex items-center justify-between px-5 py-4 gap-4">
        <p className="text-sm font-semibold text-navy-900 leading-snug">{q}</p>
        {open
          ? <ChevronUp size={17} className="flex-shrink-0 text-teal-dark" style={{ color: '#00a88a' }} />
          : <ChevronDown size={17} className="flex-shrink-0 text-slate-400" />
        }
      </div>
      {open && (
        <div className="px-5 pb-5">
          <div className="h-px mb-4" style={{ background: 'rgba(0,229,192,0.2)' }} />
          <p className="text-sm text-slate-500 leading-relaxed">{a}</p>
        </div>
      )}
    </div>
  )
}

/* ── Page ───────────────────────────────────────────── */

export default function HelpCenter() {
  const [search, setSearch] = useState('')
  const [activeCategory, setActiveCategory] = useState('all')

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  const filtered = FAQS.filter(faq => {
    const matchCat = activeCategory === 'all' || faq.category === activeCategory
    const matchSearch =
      !search.trim() ||
      faq.q.toLowerCase().includes(search.toLowerCase()) ||
      faq.a.toLowerCase().includes(search.toLowerCase())
    return matchCat && matchSearch
  })

  return (
    <div className="min-h-screen bg-slate-50">

      {/* Top bar */}
      <div className="bg-[#143b9f] ">
        <div className="max-w-5xl mx-auto flex items-center justify-between">
          <Logo size={60} />
          <Link
            to="/"
            className="flex items-center gap-2 text-sm text-white/50 hover:text-white transition-colors"
          >
            <ArrowLeft size={15} />
            Back to Home
          </Link>
        </div>
      </div>

      {/* Hero + Search */}
      <div
        className="px-6 pt-14 pb-20 text-center"
        style={{ background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)' }}
      >
        <div
          className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-semibold mb-5"
          style={{ background: 'rgba(0,229,192,0.14)', color: '#00e5c0' }}
        >
          <HelpCircle size={11} />
          Help Center
        </div>
        <h1 className="font-display text-4xl font-extrabold text-white mb-3">
          How can we help?
        </h1>
        <p className="text-white/45 max-w-sm mx-auto text-sm mb-8">
          Search our knowledge base or browse by topic below.
        </p>

        {/* Search box */}
        <div className="max-w-lg mx-auto relative">
          <Search
            size={17}
            className="absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none"
            style={{ color: '#94a3b8' }}
          />
          <input
            type="text"
            placeholder="Search for help... e.g. 'add item', 'offline billing', 'GST'"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-11 pr-4 py-4 rounded-2xl text-sm text-navy-900
                       outline-none focus:ring-2 bg-white"
            style={{ boxShadow: '0 8px 32px rgba(0,0,0,0.16)', focusRingColor: '#00e5c0' }}
          />
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-6 mt-10 pb-20">

        {/* Category chips */}
        <div className="flex flex-wrap gap-2 mb-10">
          <button
            onClick={() => setActiveCategory('all')}
            className={`px-4 py-2 rounded-xl text-xs font-semibold transition-all ${
              activeCategory === 'all'
                ? 'bg-navy-900 text-white shadow-md'
                : 'bg-white text-slate-500 border border-slate-200 hover:border-slate-300'
            }`}
          >
            All Topics
          </button>
          {CATEGORIES.map(cat => (
            <button
              key={cat.id}
              onClick={() => setActiveCategory(cat.id)}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold transition-all ${
                activeCategory === cat.id
                  ? 'text-white shadow-md'
                  : 'bg-white text-slate-500 border border-slate-200 hover:border-slate-300'
              }`}
              style={
                activeCategory === cat.id
                  ? { background: 'linear-gradient(135deg, #0d1b3e, #1a3272)' }
                  : {}
              }
            >
              {cat.icon}
              {cat.label}
            </button>
          ))}
        </div>

        {/* Results count */}
        {search && (
          <p className="text-xs text-slate-400 mb-6">
            {filtered.length} result{filtered.length !== 1 ? 's' : ''} for "{search}"
          </p>
        )}

        {/* FAQ list */}
        {filtered.length > 0 ? (
          <div className="space-y-3">
            {filtered.map((faq, i) => (
              <FAQItem key={i} q={faq.q} a={faq.a} />
            ))}
          </div>
        ) : (
          <div className="text-center py-16">
            <HelpCircle size={36} className="mx-auto mb-3 text-slate-300" />
            <p className="font-semibold text-navy-900 mb-1">No results found</p>
            <p className="text-sm text-slate-400">Try different keywords or browse all topics</p>
            <button
              onClick={() => { setSearch(''); setActiveCategory('all') }}
              className="mt-4 text-sm font-semibold transition-colors hover:opacity-80"
              style={{ color: '#00a88a' }}
            >
              Clear search
            </button>
          </div>
        )}

        {/* Contact / escalation cards */}
        <div className="mt-16 grid md:grid-cols-3 gap-5">
          {/* WhatsApp support */}
          <div
            className="rounded-2xl p-6 text-center"
            style={{
              background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)',
            }}
          >
            <MessageCircle size={26} className="mx-auto mb-3" style={{ color: '#00e5c0' }} />
            <h3 className="font-display font-bold text-white text-sm mb-1">WhatsApp Support</h3>
            <p className="text-white/40 text-xs mb-4">Chat with us for quick help</p>
            <a
              href="https://wa.me/919XXXXXXXXX"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block text-xs font-bold px-4 py-2.5 rounded-xl"
              style={{ background: '#00e5c0', color: '#0d1b3e' }}
            >
              Chat on WhatsApp
            </a>
          </div>

          {/* Email support */}
          <div className="glass rounded-2xl p-6 text-center border border-slate-200">
            <Mail size={26} className="mx-auto mb-3 text-navy-900" />
            <h3 className="font-display font-bold text-navy-900 text-sm mb-1">Email Support</h3>
            <p className="text-slate-400 text-xs mb-4">We reply within 24 hours</p>
            <a
              href="mailto:support@vengurlatech.com"
              className="inline-block text-xs font-bold px-4 py-2.5 rounded-xl bg-navy-900 text-white"
            >
              support@vengurlatech.com
            </a>
          </div>

          {/* Account deletion */}
          <div className="glass rounded-2xl p-6 text-center border border-slate-200">
            <Settings size={26} className="mx-auto mb-3 text-slate-400" />
            <h3 className="font-display font-bold text-navy-900 text-sm mb-1">Delete Account</h3>
            <p className="text-slate-400 text-xs mb-4">Request permanent data deletion</p>
            <Link
              to="/delete-account"
              className="inline-block text-xs font-bold px-4 py-2.5 rounded-xl"
              style={{ background: '#fee2e2', color: '#b91c1c' }}
            >
              Deletion Form
            </Link>
          </div>
        </div>

        {/* Footer nav */}
        <div className="flex flex-wrap justify-center gap-6 mt-12 pt-8 border-t border-slate-200 text-xs text-slate-400">
          <Link to="/" className="hover:text-navy-900 transition-colors">Home</Link>
          <Link to="/privacy" className="hover:text-navy-900 transition-colors">Privacy Policy</Link>
          <Link to="/delete-account" className="hover:text-navy-900 transition-colors">Delete Account</Link>
          <a href="mailto:support@vengurlatech.com" className="hover:text-navy-900 transition-colors">Contact</a>
        </div>
      </div>
    </div>
  )
}
