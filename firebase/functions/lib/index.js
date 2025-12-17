"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupOldData = exports.monitorHealth = exports.exportToBigQuery = exports.exportDreamToBigQuery = exports.aggregateAnalytics = exports.logUserEvent = exports.sendNotification = exports.resetDailyUsage = exports.stitchDreamFilm = exports.processDream = exports.adminGetTrends = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firestore_1 = require("firebase-functions/v2/firestore");
const bigquery_1 = require("@google-cloud/bigquery");
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const fs = __importStar(require("fs"));
const fluent_ffmpeg_1 = __importDefault(require("fluent-ffmpeg"));
const ffmpeg_1 = __importDefault(require("@ffmpeg-installer/ffmpeg"));
const openai_1 = __importDefault(require("openai"));
try {
    admin.initializeApp();
}
catch (_) { }
/**
 * Configuration:
 * Set environment variables for Cloud Functions and install the Firestore > BigQuery export
 * extension if you want automatic BigQuery sync.
 *   - BIGQUERY_PROJECT, BIGQUERY_DATASET, DREAMS_TABLE, ANALYTICS_TABLE
 *   - Install the extension for collections you wish to export
 *   - Run the extension's backfill to populate existing documents
 */
const BQ_PROJECT = process.env.BIGQUERY_PROJECT || process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
const BQ_DATASET = process.env.BIGQUERY_DATASET || 'firestore_export';
const DREAMS_TABLE = process.env.DREAMS_TABLE || 'dreams_raw_latest';
const ANALYTICS_TABLE = process.env.ANALYTICS_TABLE || 'analytics_raw_latest';
const bq = new bigquery_1.BigQuery({ projectId: BQ_PROJECT || undefined });
fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_1.default.path || ffmpeg_1.default.path);
function getOpenAI() {
    const key = process.env.OPENAI_API_KEY;
    if (!key)
        return null;
    return new openai_1.default({ apiKey: key });
}
function sanitizeText(input) {
    if (!input)
        return '';
    const s = String(input)
        .replace(/[\u0000-\u001F\u007F]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    return s.slice(0, 10000);
}
function parseGsUri(uri) {
    if (!uri.startsWith('gs://'))
        throw new Error('Expected gs:// URI');
    const without = uri.replace('gs://', '');
    const firstSlash = without.indexOf('/');
    if (firstSlash < 0) {
        return { bucket: without, name: '' };
    }
    return { bucket: without.slice(0, firstSlash), name: without.slice(firstSlash + 1) };
}
async function downloadToTmp(input) {
    const tmp = path.join(os.tmpdir(), `dl_${Date.now()}_${Math.random().toString(36).slice(2)}`);
    let fileRef;
    if (input.startsWith('gs://')) {
        fileRef = parseGsUri(input);
    }
    else {
        const b = admin.storage().bucket().name;
        fileRef = { bucket: b, name: input.replace(/^\//, '') };
    }
    const bucket = admin.storage().bucket(fileRef.bucket);
    await bucket.file(fileRef.name).download({ destination: tmp });
    return tmp;
}
async function uploadFromTmp(tmpPath, destPath, contentType) {
    const bucket = admin.storage().bucket();
    await bucket.upload(tmpPath, { destination: destPath, metadata: { contentType } });
    return `gs://${bucket.name}/${destPath}`;
}
async function getSignedUrl(gsPath, expiresInHours = 24) {
    const { bucket, name } = parseGsUri(gsPath);
    const [url] = await admin
        .storage()
        .bucket(bucket)
        .file(name)
        .getSignedUrl({ action: 'read', expires: Date.now() + expiresInHours * 3600 * 1000 });
    return url;
}
async function isAdmin(uid) {
    try {
        const token = await admin.auth().getUser(uid);
        const claimAdmin = token.customClaims?.['admin'] === true;
        if (claimAdmin)
            return true;
    }
    catch (e) { }
    try {
        const doc = await admin.firestore().collection('users').doc(uid).get();
        const roles = doc.get('roles') || {};
        if (roles && roles['admin'] === true)
            return true;
    }
    catch (e) { }
    return false;
}
function parseRangeToDays(range) {
    if (!range)
        return 30;
    const m = range.match(/^(\d+)d$/i);
    if (m)
        return Math.max(1, parseInt(m[1], 10));
    return 30;
}
exports.adminGetTrends = (0, https_1.onCall)({ region: 'us-central1' }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new Error('UNAUTHENTICATED');
    }
    const ok = await isAdmin(uid);
    if (!ok) {
        throw new Error('PERMISSION_DENIED');
    }
    const days = parseRangeToDays(request.data?.range || '30d');
    const fullDreamsTable = `\`${BQ_PROJECT}.${BQ_DATASET}.${DREAMS_TABLE}\``;
    const fullAnalyticsTable = `\`${BQ_PROJECT}.${BQ_DATASET}.${ANALYTICS_TABLE}\``;
    const dailyDreamsSql = `
    WITH base AS (
      SELECT
        COALESCE(
          TIMESTAMP_SECONDS(CAST(JSON_VALUE(data.createdAt._seconds) AS INT64)),
          TIMESTAMP(JSON_VALUE(data.createdAt)) ,
          timestamp
        ) AS created_ts
      FROM ${fullDreamsTable}
      WHERE JSON_VALUE(data.archived) IS NULL OR JSON_VALUE(data.archived) = 'false'
    )
    SELECT
      FORMAT_DATE('%Y-%m-%d', DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY) + (d)) AS day,
      (SELECT COUNT(1) FROM base WHERE DATE(created_ts) = DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY) + (d)) AS count
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY), CURRENT_DATE())) AS d
    ORDER BY day
  `;
    const topTagsSql = `
    SELECT LOWER(TRIM(tag)) AS tag, COUNT(1) AS count
    FROM (
      SELECT * FROM ${fullDreamsTable}
    ), UNNEST(
      ARRAY(
        SELECT AS STRUCT JSON_VALUE(x) FROM UNNEST(JSON_QUERY_ARRAY(data.tags)) AS x
      )
    ) AS t(tag)
    WHERE tag IS NOT NULL AND tag != ''
    GROUP BY tag
    ORDER BY count DESC
    LIMIT 20
  `;
    const dauSql = `
    WITH base AS (
      SELECT COALESCE(
        TIMESTAMP_SECONDS(CAST(JSON_VALUE(data.timestamp._seconds) AS INT64)),
        TIMESTAMP(JSON_VALUE(data.timestamp)),
        timestamp
      ) AS ts,
      JSON_VALUE(data.eventType) AS eventType,
      JSON_VALUE(data.userId) AS userId
      FROM ${fullAnalyticsTable}
    )
    SELECT
      FORMAT_DATE('%Y-%m-%d', DATE(ts)) AS day,
      COUNT(DISTINCT userId) AS users
    FROM base
    WHERE DATE(ts) >= DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY)
    GROUP BY day
    ORDER BY day
  `;
    const avgProcessingSql = `
    SELECT AVG(CAST(JSON_VALUE(data.metadata.processingSeconds) AS FLOAT64)) AS avgSeconds
    FROM ${fullDreamsTable}
    WHERE JSON_VALUE(data.metadata.processingSeconds) IS NOT NULL
  `;
    const options = { location: 'US', params: { days } };
    const [dailyDreams, topTags, dau, avgProc] = await Promise.all([
        bq.query({ query: dailyDreamsSql, ...options }),
        bq.query({ query: topTagsSql, ...options }),
        bq.query({ query: dauSql, ...options }),
        bq.query({ query: avgProcessingSql, ...options }),
    ]);
    const dailyDreamsRows = dailyDreams[0];
    const topTagsRows = topTags[0];
    const dauRows = dau[0];
    const avgProcRows = avgProc[0];
    const resp = {
        dailyDreams: dailyDreamsRows.map((r) => ({ day: r.day, count: Number(r.count || 0) })),
        topTags: topTagsRows.map((r) => ({ tag: r.tag, count: Number(r.count || 0) })),
        activeUsersDaily: dauRows.map((r) => ({ day: r.day, users: Number(r.users || 0) })),
        activeUsersToday: (() => {
            const today = dauRows.find((r) => r.day === new Date().toISOString().slice(0, 10));
            return today ? Number(today.users || 0) : 0;
        })(),
        avgProcessingSeconds: avgProcRows?.[0]?.avgSeconds ? Number(avgProcRows[0].avgSeconds) : 0,
    };
    return resp;
});
exports.processDream = (0, firestore_1.onDocumentCreated)({ region: 'us-central1', document: 'dreams/{dreamId}' }, async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const dreamId = event.params.dreamId;
    const data = snap.data();
    const uid = data.userId || data.uid;
    const ref = snap.ref;
    const rawText = sanitizeText(data.rawText || data.text || '');
    const now = admin.firestore.Timestamp.now();
    await ref.set({
        rawText,
        status: 'processing',
        metadata: {
            ...(data.metadata || {}),
            processingStartedAt: now,
            stages: { created: now.toDate().toISOString(), interpreting: 'started' },
        },
        updatedAt: now,
    }, { merge: true });
    const openai = getOpenAI();
    let analysis = null;
    if (openai && rawText.length > 0) {
        try {
            const sys = 'You are a psychologist and expert dream interpreter. Return compact JSON with keys: summary, symbols[], emotions[], tags[], advice.';
            const prompt = `Analyze the following dream journal entry. Be concise.\n\nEntry: ${rawText}`;
            const comp = await openai.chat.completions.create({
                model: 'gpt-4o-mini',
                temperature: 0.4,
                response_format: { type: 'json_object' },
                messages: [
                    { role: 'system', content: sys },
                    { role: 'user', content: prompt },
                ],
            });
            const content = comp.choices?.[0]?.message?.content || '{}';
            try {
                analysis = JSON.parse(content);
            }
            catch (_) {
                analysis = { summary: content };
            }
        }
        catch (e) {
            console.error('processDream: GPT analysis failed', e);
            analysis = { error: 'analysis_failed' };
        }
    }
    let visualStatus = { status: 'queued' };
    const soraUrl = process.env.SORA_API_URL;
    const soraKey = process.env.SORA_API_KEY;
    if (soraUrl && soraKey) {
        try {
            const resp = await globalThis.fetch(soraUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${soraKey}` },
                body: JSON.stringify({
                    dreamId,
                    prompt: analysis?.summary || rawText.slice(0, 512),
                    durationSec: Number(data?.metadata?.requestedDurationSec || 20),
                    aspect: '16:9',
                }),
            });
            const json = await resp.json().catch(() => ({}));
            visualStatus = { status: 'generating', jobId: json?.jobId || null };
        }
        catch (e) {
            console.error('processDream: visual enqueue failed', e);
            visualStatus = { status: 'queued' };
        }
    }
    const after = admin.firestore.Timestamp.now();
    const processingSeconds = (after.seconds - now.seconds) + (after.nanoseconds - now.nanoseconds) / 1e9;
    await ref.set({
        metadata: {
            ...(data.metadata || {}),
            analysis,
            visual: visualStatus,
            processingSeconds,
            stages: { ...(data.metadata?.stages || {}), interpreting: 'done' },
        },
        status: 'processed',
        updatedAt: after,
    }, { merge: true });
    if (uid) {
        await admin
            .firestore()
            .collection('users')
            .doc(uid)
            .collection('analytics')
            .add({ eventType: 'dream_processed', timestamp: admin.firestore.FieldValue.serverTimestamp(), dreamId });
    }
});
exports.stitchDreamFilm = (0, https_1.onRequest)({ region: 'us-central1', timeoutSeconds: 540, memory: '1GiB' }, async (req, res) => {
    try {
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
        res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        if (req.method === 'OPTIONS')
            return res.status(204).send('');
        const auth = req.headers.authorization || '';
        const requiredToken = process.env.STITCH_TOKEN;
        if (requiredToken && auth !== `Bearer ${requiredToken}`) {
            return res.status(401).json({ error: 'unauthorized' });
        }
        const { dreamId, segments, outPath, fps = 24, width = 1280, height = 720 } = req.body || {};
        if (!dreamId || !Array.isArray(segments) || segments.length === 0) {
            return res.status(400).json({ error: 'invalid_request' });
        }
        const finalPath = outPath || `dreams/${dreamId}/film.mp4`;
        const tmpFiles = [];
        for (const s of segments) {
            const p = await downloadToTmp(String(s));
            tmpFiles.push(p);
        }
        const listPath = path.join(os.tmpdir(), `concat_${Date.now()}.txt`);
        fs.writeFileSync(listPath, tmpFiles.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join('\n'));
        const outTmp = path.join(os.tmpdir(), `out_${Date.now()}.mp4`);
        await new Promise((resolve, reject) => {
            (0, fluent_ffmpeg_1.default)()
                .input(listPath)
                .inputOptions(['-f', 'concat', '-safe', '0'])
                .videoCodec('libx264')
                .size(`${width}x${height}`)
                .fps(fps)
                .outputOptions(['-movflags', 'faststart'])
                .format('mp4')
                .on('error', (err) => reject(err))
                .on('end', () => resolve())
                .save(outTmp);
        });
        const gs = await uploadFromTmp(outTmp, finalPath, 'video/mp4');
        const url = await getSignedUrl(gs, 168);
        await admin.firestore().collection('dreams').doc(dreamId).set({
            metadata: { visual: { status: 'ready', path: gs, signedUrl: url } },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        res.json({ ok: true, gsPath: gs, url });
    }
    catch (e) {
        console.error('stitchDreamFilm error', e);
        res.status(500).json({ error: 'internal', details: String(e?.message || e) });
    }
});
exports.resetDailyUsage = (0, scheduler_1.onSchedule)({ region: 'us-central1', schedule: 'every day 00:10', timeZone: 'Etc/UTC' }, async () => {
    const db = admin.firestore();
    const usersRef = db.collection('users');
    const pageSize = 500;
    let last = null;
    while (true) {
        let q = usersRef.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => {
            batch.set(doc.ref, {
                dailyUsage: { videos: 0, seconds: 0, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
                lastDailyResetAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        await batch.commit();
        last = snap.docs[snap.docs.length - 1];
    }
});
exports.sendNotification = (0, firestore_1.onDocumentUpdated)({ region: 'us-central1', document: 'dreams/{dreamId}' }, async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after)
        return;
    const uid = after.userId || after.uid;
    if (!uid)
        return;
    const statusChanged = before.status !== after.status && (after.status === 'processed' || after.status === 'completed');
    const visualReady = before?.metadata?.visual?.status !== after?.metadata?.visual?.status && after?.metadata?.visual?.status === 'ready';
    if (!statusChanged && !visualReady)
        return;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const tokens = userDoc.get('fcmTokens') || [];
    if (!tokens.length)
        return;
    const title = 'Your dream is ready';
    const body = visualReady ? 'Your dream film is ready to watch.' : 'Your dream interpretation is complete.';
    await admin.messaging().sendMulticast({
        tokens,
        notification: { title, body },
        data: { dreamId: event.params.dreamId },
    });
});
exports.logUserEvent = (0, https_1.onCall)({ region: 'us-central1' }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new Error('UNAUTHENTICATED');
    const { eventType, details } = (request.data || {});
    if (!eventType)
        throw new Error('INVALID_ARGUMENT');
    const db = admin.firestore();
    const ref = await db.collection('users').doc(uid).collection('analytics').add({
        eventType,
        details: details || {},
        userId: uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { id: ref.id };
});
exports.aggregateAnalytics = (0, scheduler_1.onSchedule)({ region: 'us-central1', schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
    const db = admin.firestore();
    const since = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 3600 * 1000));
    const snap = await db.collectionGroup('analytics').where('timestamp', '>=', since).get();
    const counters = new Map();
    const uniqueUsers = new Set();
    snap.forEach((d) => {
        const e = d.get('eventType') || 'unknown';
        counters.set(e, (counters.get(e) || 0) + 1);
        const uid = d.get('userId') || d.ref.parent.parent?.id || '';
        if (uid)
            uniqueUsers.add(uid);
    });
    const dayKey = new Date().toISOString().slice(0, 10);
    await db.collection('analytics').doc('daily').collection('days').doc(dayKey).set({
        day: dayKey,
        eventCounts: Object.fromEntries(counters),
        activeUsers: uniqueUsers.size,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    try {
        const rows = Array.from(counters.entries()).map(([eventType, count]) => ({ day: dayKey, eventType, count }));
        if (rows.length && BQ_PROJECT) {
            const dataset = bq.dataset(BQ_DATASET);
            const table = dataset.table('daily_event_counts');
            await table.insert(rows);
        }
    }
    catch (e) {
        console.error('aggregateAnalytics BigQuery export failed', e);
    }
});
exports.exportDreamToBigQuery = (0, firestore_1.onDocumentWritten)({ region: 'us-central1', document: 'dreams/{dreamId}' }, async (event) => {
    try {
        const after = event.data?.after?.data();
        if (!after)
            return;
        const dataset = bq.dataset(BQ_DATASET);
        const table = dataset.table(DREAMS_TABLE);
        await table.insert([{ ...after, dreamId: event.params.dreamId, changedAt: new Date().toISOString() }]);
    }
    catch (e) {
        console.error('exportDreamToBQ failed', e);
    }
});
exports.exportToBigQuery = (0, firestore_1.onDocumentWritten)({ region: 'us-central1', document: 'users/{uid}/analytics/{eventId}' }, async (event) => {
    try {
        const after = event.data?.after?.data();
        if (!after)
            return;
        const dataset = bq.dataset(BQ_DATASET);
        const table = dataset.table(ANALYTICS_TABLE);
        await table.insert([{ ...after, eventId: event.params.eventId, changedAt: new Date().toISOString() }]);
    }
    catch (e) {
        console.error('exportAnalyticsToBQ failed', e);
    }
});
exports.monitorHealth = (0, scheduler_1.onSchedule)({ region: 'us-central1', schedule: 'every 15 minutes', timeZone: 'Etc/UTC' }, async () => {
    const db = admin.firestore();
    const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 60 * 60 * 1000));
    const stuckSnap = await db.collection('dreams').where('status', 'in', ['processing', 'processed']).where('updatedAt', '<', cutoff).limit(20).get();
    if (stuckSnap.empty)
        return;
    const webhook = process.env.SLACK_WEBHOOK_URL;
    const lines = stuckSnap.docs.map((d) => `• ${d.id} (status=${d.get('status')})`).join('\n');
    const text = `DreamWeaver monitor: ${stuckSnap.size} potentially stuck dreams:\n${lines}`;
    if (webhook) {
        try {
            await globalThis.fetch(webhook, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }) });
        }
        catch (e) {
            console.error('monitorHealth slack failed', e);
        }
    }
    else {
        console.warn('monitorHealth: SLACK_WEBHOOK_URL not set');
    }
});
exports.cleanupOldData = (0, scheduler_1.onSchedule)({ region: 'us-central1', schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
    const db = admin.firestore();
    const cutoffDate = new Date(Date.now() - 180 * 24 * 3600 * 1000);
    const cutoff = admin.firestore.Timestamp.fromDate(cutoffDate);
    const snap = await db.collection('dreams').where('createdAt', '<=', cutoff).where('archived', '!=', true).limit(1000).get();
    if (snap.empty)
        return;
    const batch = db.batch();
    snap.docs.forEach((doc) => {
        batch.set(doc.ref, { archived: true, archivedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    });
    await batch.commit();
});
//# sourceMappingURL=index.js.map