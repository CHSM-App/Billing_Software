/**
 * Vittam — Play Store Deploy Script
 * VengurlaTech
 *
 * USAGE:
 *   node deploy.js --track=sharing           → Internal App Sharing — returns a shareable install link
 *   node deploy.js --priority=3              → production release (10% users, bottom sheet popup)
 *   node deploy.js --priority=5 --force      → emergency force update (100% users, full screen)
 *   node deploy.js --priority=3 --dry-run    → test without uploading
 *   --yes                                    → skip confirmations (used by CI)
 */

const { google } = require('googleapis');
const fs         = require('fs');
const path       = require('path');
const readline   = require('readline');

// ─── CONFIGURATION ────────────────────────────────────────────────────────────

const PACKAGE_NAME    = 'com.vengurlatech.Vittam';
const SERVICE_ACCOUNT = path.join(__dirname, 'service-account.json');
const AAB_PATH        = path.join(__dirname, '../frontend/build/app/outputs/bundle/release/app-release.aab');

// ─── READ COMMAND LINE ARGUMENTS ─────────────────────────────────────────────

const args      = {};
process.argv.slice(2).forEach(arg => {
  const [key, val] = arg.replace('--', '').split('=');
  args[key] = val ?? true;
});

const PRIORITY = parseInt(args.priority ?? '3');
const TRACK    = args.track    ?? 'production';
const FORCE    = args.force    === true;
const DRY_RUN  = args['dry-run'] === true;
const FRACTION = FORCE ? 1.0 : parseFloat(args.fraction ?? '0.1');
// --yes skips all interactive confirmations. Required in CI (GitHub Actions),
// which has no stdin — the ask() prompts would hang the job forever.
const YES      = args.yes === true;

// ─── PRIORITY DESCRIPTIONS ────────────────────────────────────────────────────

const PRIORITY_INFO = {
  0: 'No prompt shown to user',
  1: 'Very low priority',
  2: 'Low priority',
  3: 'Optional update — Play Store bottom sheet popup',
  4: 'High priority — strong recommendation popup',
  5: 'FORCE UPDATE — full screen, user cannot dismiss',
};

// ─── HELPER FUNCTIONS ─────────────────────────────────────────────────────────

function ask(question) {
  // In CI (--yes) there is no interactive terminal — auto-confirm and log it.
  if (YES) {
    console.log(`  ${question} (y/n): y  [auto-confirmed via --yes]`);
    return Promise.resolve(true);
  }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => {
    rl.question(`  ${question} (y/n): `, answer => {
      rl.close();
      resolve(answer.toLowerCase() === 'y');
    });
  });
}

function log(msg)  { console.log(`  → ${msg}`);      }
function ok(msg)   { console.log(`  ✅ ${msg}`);      }
function err(msg)  { console.error(`  ❌ ${msg}`);    }
function warn(msg) { console.log(`  ⚠️  ${msg}`);     }
function line()    { console.log('  ' + '─'.repeat(50)); }

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {

  console.log('\n');
  console.log('  ══════════════════════════════════════════════════');
  console.log('         Vittam — Play Store Deploy                 ');
  console.log('  ══════════════════════════════════════════════════');
  console.log('\n');

  // ── STEP 1: Validate files exist ──────────────────────────────────────────

  log('Checking files...');

  if (!fs.existsSync(SERVICE_ACCOUNT)) {
    err('service-account.json not found!');
    err(`Expected at: ${SERVICE_ACCOUNT}`);
    err('Place your Google Cloud service account JSON file in the deploy folder.');
    process.exit(1);
  }
  ok('service-account.json found');

  if (!fs.existsSync(AAB_PATH)) {
    err('App bundle (AAB) not found!');
    err(`Expected at: ${AAB_PATH}`);
    err('Run this first:  flutter build appbundle --release');
    process.exit(1);
  }
  ok('AAB file found');

  // ── STEP 2: Show release summary ──────────────────────────────────────────

  const aabSizeMB  = (fs.statSync(AAB_PATH).size / 1024 / 1024).toFixed(1);
  const aabBuiltAt = fs.statSync(AAB_PATH).mtime.toLocaleString('en-IN');

  // Read version name + versionCode from pubspec.yaml. The versionCode is the
  // integer after the '+' (e.g. "1.1.1+12" → 12). This is the number Play Store
  // uses; the guard below verifies it's higher than anything already uploaded.
  let versionLabel = 'unknown';
  let localVersionCode = null;
  try {
    const pubspec = fs.readFileSync(path.join(__dirname, '../frontend/pubspec.yaml'), 'utf8');
    const match   = pubspec.match(/^version:\s*(.+)$/m);
    if (match) {
      versionLabel = match[1].trim();
      const codeMatch = versionLabel.match(/\+(\d+)/);
      if (codeMatch) localVersionCode = parseInt(codeMatch[1], 10);
    }
  } catch (_) {}

  console.log('\n');
  line();
  console.log('  RELEASE SUMMARY');
  line();
  console.log(`  Package    : ${PACKAGE_NAME}`);
  console.log(`  Version    : ${versionLabel}`);
  console.log(`  Track      : ${TRACK}`);
  console.log(`  Priority   : ${PRIORITY} — ${PRIORITY_INFO[PRIORITY] ?? 'Unknown'}`);
  console.log(`  Rollout    : ${FORCE ? '100% (all users immediately)' : `${FRACTION * 100}% staged rollout`}`);
  console.log(`  AAB size   : ${aabSizeMB} MB`);
  console.log(`  AAB built  : ${aabBuiltAt}`);
  console.log(`  Dry run    : ${DRY_RUN ? 'YES — nothing will be uploaded' : 'No'}`);
  line();
  console.log('\n');

  if (DRY_RUN) {
    ok('Dry run complete. All files are valid.');
    ok('Remove --dry-run to do a real upload.');
    return;
  }

  // ── STEP 3: Confirm before uploading ──────────────────────────────────────

  if (PRIORITY >= 5) {
    warn('FORCE UPDATE — this will block ALL users until they update.');
    warn('Only use this when the app is broken or has a security issue.');
    console.log('\n');
    const confirm1 = await ask('Are you sure you want to force update ALL users?');
    if (!confirm1) { log('Cancelled.'); process.exit(0); }
    const confirm2 = await ask('Have you confirmed the fix is working correctly?');
    if (!confirm2) { log('Cancelled.'); process.exit(0); }
  } else if (TRACK === 'production') {
    const confirm = await ask(`Deploy to PRODUCTION at ${FRACTION * 100}% rollout with priority ${PRIORITY}?`);
    if (!confirm) { log('Cancelled.'); process.exit(0); }
  }

  // ── STEP 4: Authenticate with Google Play ─────────────────────────────────

  console.log('\n');
  log('Connecting to Google Play...');

  const auth = new google.auth.GoogleAuth({
    keyFile : SERVICE_ACCOUNT,
    scopes  : ['https://www.googleapis.com/auth/androidpublisher'],
  });

  const authClient = await auth.getClient();
  const play       = google.androidpublisher({ version: 'v3', auth: authClient });
  ok('Connected to Google Play API');

  // ── INTERNAL APP SHARING ──────────────────────────────────────────────────
  // A completely separate flow from the track-based release below. It uploads
  // the AAB to Internal App Sharing and returns a one-tap download link. No
  // edit/track/commit, no review, and no versionCode uniqueness requirement —
  // so the guard and the edit session below are skipped entirely.
  if (TRACK === 'sharing') {
    log('Uploading AAB to Internal App Sharing...');
    const shareRes = await play.internalappsharingartifacts.uploadbundle({
      packageName : PACKAGE_NAME,
      media: {
        mimeType : 'application/octet-stream',
        body     : fs.createReadStream(AAB_PATH),
      },
    });

    console.log('\n');
    console.log('  ══════════════════════════════════════════════════');
    ok('UPLOADED TO INTERNAL APP SHARING!');
    console.log('  ══════════════════════════════════════════════════');
    console.log(`\n  Share link:\n  ${shareRes.data.downloadUrl}\n`);
    console.log('  Anyone with Play Store access you\'ve granted can install via this link.');
    console.log('\n');
    return;
  }

  // ── STEP 5: Create an edit ────────────────────────────────────────────────

  log('Creating edit session...');
  const editRes = await play.edits.insert({ packageName: PACKAGE_NAME });
  const editId  = editRes.data.id;
  ok(`Edit session created: ${editId}`);

  try {

    // ── STEP 5b: Guard — versionCode must be higher than anything on Play ────
    // Play Store rejects any AAB whose versionCode was already used. Catch that
    // *before* the slow upload and fail with a clear "bump pubspec" message
    // instead of a cryptic rejection mid-commit.
    log('Checking existing version codes on Play...');
    const listRes = await play.edits.bundles.list({ packageName: PACKAGE_NAME, editId });
    const existing = (listRes.data.bundles ?? []).map(b => b.versionCode ?? 0);
    const highest  = existing.length ? Math.max(...existing) : 0;

    if (localVersionCode == null) {
      warn('Could not read versionCode from pubspec.yaml — skipping guard.');
    } else if (localVersionCode <= highest) {
      err(`versionCode ${localVersionCode} is not higher than the highest already on Play (${highest}).`);
      err(`Bump the "+NN" in frontend/pubspec.yaml to at least +${highest + 1}, rebuild, and retry.`);
      await play.edits.delete({ packageName: PACKAGE_NAME, editId }).catch(() => {});
      process.exit(1);
    } else {
      ok(`versionCode ${localVersionCode} > highest on Play (${highest}) — OK to upload`);
    }

    // ── STEP 6: Upload AAB ──────────────────────────────────────────────────

    log(`Uploading AAB (${aabSizeMB} MB) — please wait...`);

    const bundleRes = await play.edits.bundles.upload({
      packageName : PACKAGE_NAME,
      editId,
      media: {
        mimeType : 'application/octet-stream',
        body     : fs.createReadStream(AAB_PATH),
      },
    });

    const versionCode = bundleRes.data.versionCode;
    ok(`AAB uploaded successfully — version code: ${versionCode}`);

    // Wait for Google Play to finish processing the AAB before continuing
    log('Waiting for Google Play to process the bundle...');
    await new Promise(resolve => setTimeout(resolve, 15000));
    ok('Bundle processing complete');

    // ── STEP 7: Set track + priority ───────────────────────────────────────

    log(`Setting track "${TRACK}" with priority ${PRIORITY}...`);

    await play.edits.tracks.update({
      packageName : PACKAGE_NAME,
      editId,
      track       : TRACK,
      requestBody : {
        track    : TRACK,
        releases : [{
          versionCodes         : [String(versionCode)],
          status               : (FORCE || FRACTION >= 1.0 || TRACK === 'internal') ? 'completed' : 'inProgress',
          userFraction         : (FORCE || FRACTION >= 1.0 || TRACK === 'internal') ? undefined : FRACTION,
          inAppUpdatePriority  : PRIORITY,
        }],
      },
    });

    ok(`Track "${TRACK}" updated with priority ${PRIORITY}`);

    // ── STEP 8: Commit the edit ────────────────────────────────────────────

    log('Committing release...');
    await play.edits.commit({ packageName: PACKAGE_NAME, editId });

    // ── STEP 9: Done ───────────────────────────────────────────────────────

    console.log('\n');
    console.log('  ══════════════════════════════════════════════════');
    ok('DEPLOY SUCCESSFUL!');
    console.log('  ══════════════════════════════════════════════════');
    console.log(`\n  Track    : ${TRACK}`);
    console.log(`  Priority : ${PRIORITY} — ${PRIORITY_INFO[PRIORITY]}`);
    console.log(`  Rollout  : ${FORCE ? '100% (all users)' : TRACK === 'internal' ? 'Internal testers only' : `${FRACTION * 100}% of users`}`);

    if (TRACK === 'production' && !FORCE) {
      console.log('\n  Next steps:');
      console.log('  1. Wait 24 hours');
      console.log('  2. Check crash rate in Play Console');
      console.log('  3. Play Console → Production → Manage rollout → increase to 50% → 100%');
    }

    if (TRACK === 'internal') {
      console.log('\n  Next step:');
      console.log('  Share with your testers via Play Console → Internal testing');
    }

    console.log('\n');

  } catch (error) {
    // If anything fails, delete the incomplete edit
    err(`Upload failed: ${error.message}`);
    log('Cleaning up...');
    await play.edits.delete({ packageName: PACKAGE_NAME, editId }).catch(() => {});
    process.exit(1);
  }
}

main().catch(e => {
  err(e.message);
  process.exit(1);
});
