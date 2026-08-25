/**
 * Onboarding steps, in a plain .js module (no JSX) so both the "How It Works"
 * section and prerender.js — which runs in bare Node — can import them. Keeps
 * the rendered steps and the HowTo structured data from drifting apart.
 */
export const STEPS = [
  {
    num: '01',
    title: 'Set Up Your Store',
    desc: 'Add your business profile, inventory items, categories, and staff in minutes. No training required.',
  },
  {
    num: '02',
    title: 'Start Billing',
    desc: 'Search or tap items, adjust quantities, select payment mode, and generate bills with a single tap.',
  },
  {
    num: '03',
    title: 'Track & Grow',
    desc: 'Review daily reports, monitor expenses, and watch your business insights improve every single day.',
  },
]
