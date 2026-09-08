import http from 'k6/http';
import { check, group } from 'k6';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate==1.0'],
    http_req_duration: ['p(95)<2000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://pmon.dev';
const KEYCLOAK_URL = __ENV.KEYCLOAK_URL || 'https://auth.pmon.dev';

// Every group below, public first. K6_SKIP_GROUPS="chat,chess" skips groups
// whose service is not deployed in this environment (e.g. the Vagrant DR
// drill runs monitor + site only). Validated in init so a typo or an
// over-broad list aborts the run (k6 exit 107) instead of passing vacuously;
// 'health' is the floor and can never be skipped.
const PUBLIC_GROUPS = ['health', 'approval-mode', 'permissions', 'keycloak', 'frontend', 'actuator'];
const AUTH_GROUPS = ['monitors', 'rss', 'inbox', 'chat', 'chess'];
const SKIP = new Set((__ENV.K6_SKIP_GROUPS || '').split(',').map((s) => s.trim()).filter(Boolean));
for (const name of SKIP) {
  if (!PUBLIC_GROUPS.includes(name) && !AUTH_GROUPS.includes(name)) {
    throw new Error(`K6_SKIP_GROUPS: unknown group '${name}' (known: ${PUBLIC_GROUPS.concat(AUTH_GROUPS).join(', ')})`);
  }
}
if (SKIP.has('health')) {
  throw new Error("K6_SKIP_GROUPS: 'health' cannot be skipped");
}

function smoke(name, fn) {
  if (SKIP.has(name)) {
    console.log(`group '${name}' skipped (K6_SKIP_GROUPS)`);
    return;
  }
  group(name, fn);
}

function getToken() {
  const clientSecret = __ENV.K6_CLIENT_SECRET;
  if (!clientSecret) {
    console.log('K6_CLIENT_SECRET not set, skipping authenticated tests');
    return null;
  }
  const res = http.post(`${KEYCLOAK_URL}/realms/schnappy/protocol/openid-connect/token`, {
    client_id: 'k6-smoke',
    client_secret: clientSecret,
    grant_type: 'client_credentials',
  }, { tags: { name: 'token' } });
  // A configured secret that yields no token is a failure, not a skip: otherwise
  // a Keycloak missing the k6-smoke client passes on the public checks alone.
  check(res, { 'token obtained': (r) => r.status === 200 });
  if (res.status !== 200) {
    console.error(`Token request failed: ${res.status} ${res.body}`);
    return null;
  }
  return res.json('access_token');
}

export default function smokeTest() {
  // ===== Public endpoints =====

  smoke('health', () => {
    const r = http.get(`${BASE_URL}/api/health`);
    check(r, {
      'health 200': (r) => r.status === 200,
      'status UP': (r) => r.json('status') === 'UP',
    });
  });

  smoke('approval-mode', () => {
    const r = http.get(`${BASE_URL}/api/auth/approval-mode`);
    check(r, { 'approval-mode 200': (r) => r.status === 200 });
  });

  smoke('permissions', () => {
    const r = http.get(`${BASE_URL}/api/permissions/required`);
    check(r, { 'permissions 200': (r) => r.status === 200 });
  });

  smoke('keycloak', () => {
    const kcPublicUrl = __ENV.KEYCLOAK_PUBLIC_URL || KEYCLOAK_URL;
    const r = http.get(`${kcPublicUrl}/realms/schnappy/.well-known/openid-configuration`);
    check(r, {
      'keycloak 200': (r) => r.status === 200,
      'has issuer': (r) => r.json('issuer') !== undefined,
    });
  });

  smoke('frontend', () => {
    const r = http.get(`${BASE_URL}/`);
    check(r, { 'frontend 200': (r) => r.status === 200 });
  });

  smoke('actuator', () => {
    const r = http.get(`${BASE_URL}/api/actuator/health/readiness`);
    check(r, { 'actuator-readiness 200': (r) => r.status === 200 });
  });

  // ===== Authenticated endpoints =====

  if (AUTH_GROUPS.every((g) => SKIP.has(g))) return;
  const token = getToken();
  if (!token) return;

  const auth = { headers: { Authorization: `Bearer ${token}` } };

  smoke('monitors', () => {
    const r = http.get(`${BASE_URL}/api/monitor/pages`, auth);
    check(r, { 'pages 200': (r) => r.status === 200 });
  });

  smoke('rss', () => {
    const r = http.get(`${BASE_URL}/api/rss/feeds`, auth);
    check(r, { 'feeds 200': (r) => r.status === 200 });
  });

  smoke('inbox', () => {
    const r = http.get(`${BASE_URL}/api/inbox/emails`, auth);
    check(r, { 'inbox 200': (r) => r.status === 200 });
  });

  smoke('chat', () => {
    const r = http.get(`${BASE_URL}/api/chat/channels`, auth);
    check(r, { 'channels 200': (r) => r.status === 200 });
  });

  smoke('chess', () => {
    const r = http.get(`${BASE_URL}/api/chess/games`, auth);
    check(r, { 'chess-games 200': (r) => r.status === 200 });
  });
}
