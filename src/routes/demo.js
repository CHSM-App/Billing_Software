const { Router } = require('express');
const express = require('express');
const logger = require('../logger');
const { sendDemoRequest } = require('../whatsapp');
const { demoLimiter } = require('../middleware/rateLimiter');

const router = Router();

// The landing page offers a fixed list; anything else is a hand-crafted post.
// Kept as a length cap rather than an enum so marketing can add an option to
// the page without a backend deploy.
const MAX_FIELD = 120;

const str = (v) => (typeof v === 'string' ? v.trim() : '');

// ---------------------------------------------------------------------------
// POST /api/demo/request — "Book Demo" form on the landing page.
//
// Unauthenticated and public, so every field is validated here regardless of
// what the browser already checked. Sends WhatsApp template 677 to the admin;
// nothing is stored — the message IS the record, same as the onboarding alert.
// ---------------------------------------------------------------------------
router.post('/request', demoLimiter, express.json(), async (req, res) => {
  const body = req.body || {};
  const name = str(body.name);
  const mobile = str(body.mobile).replace(/\D/g, '');
  const businessType = str(body.businessType);
  const date = str(body.date);
  const time = str(body.time);
  // The only optional one — "am I already using billing software" may be blank.
  const currentSoftware = str(body.usingSoftware) || str(body.currentSoftware);

  if (!name || name.length > MAX_FIELD) {
    return res.status(400).json({ error: 'Please enter your name' });
  }
  // Indian mobile numbers start 6-9. Same rule the form applies, restated here
  // because the form is a browser and this endpoint is reachable without one.
  if (!/^[6-9]\d{9}$/.test(mobile)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit mobile number' });
  }
  for (const [label, value] of Object.entries({
    'business type': businessType, date, time,
  })) {
    if (!value || value.length > MAX_FIELD) {
      return res.status(400).json({ error: `Please select a valid ${label}` });
    }
  }
  if (currentSoftware.length > MAX_FIELD) {
    return res.status(400).json({ error: 'Please select a valid option' });
  }

  // Fire-and-forget on the RESULT, not the await: a provider outage must not
  // show the visitor an error for a form they filled in correctly. The failure
  // is logged inside sendDemoRequest and visible in the logs.
  const result = await sendDemoRequest({
    name, mobile, businessType, date, time,
    currentSoftware: currentSoftware || 'Not specified',
  });
  if (!result.sent && !result.skipped) {
    logger.warn({ result, name }, 'Demo request alert not delivered');
  }

  return res.status(201).json({ ok: true });
});

module.exports = router;
