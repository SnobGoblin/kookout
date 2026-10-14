// Accounts: Sign in with Apple. Only needed to share and edit spots; everything else works without one.
//
//   POST   /auth/apple  {identityToken, authorizationCode?, givenName?}  -> {token, user}
//          The app signs in with Apple and sends us Apple's identity token (a JWT signed by Apple). We check it
//          against Apple's public keys and that it was made for this app, then give the app our own session token.
//   GET    /me          -> {user}                       (Authorization: Bearer <session token>)
//   PUT    /me          {name}  -> {user}              the public name, shown on shared spots and in the log
//   DELETE /me          delete the account: tells Apple to revoke the sign-in, deletes the user and sessions
//
// We store Apple's stable user id ("sub") and the public name the person chooses. No email address.
// Revoking at deletion needs Apple's refresh token, which we get by exchanging the authorization code; that needs
// a Sign in with Apple key (secret SIWA_KEY, vars SIWA_KEY_ID). Without it, sign-in still works and deletion
// deletes our data, but Apple keeps listing Kookout under the person's "Sign in with Apple" apps until they remove it.

const APPLE = "https://appleid.apple.com";

export async function handleAuth(request, env, url, reply) {
  if (url.pathname === "/auth/apple" && request.method === "POST") return signIn(request, env, reply);
  if (url.pathname === "/me") {
    const user = await currentUser(request, env);
    if (!user) return reply({ error: "not signed in" }, 401);
    if (request.method === "GET") return reply({ user: publicUser(user) });
    if (request.method === "PUT") {
      const b = await request.json().catch(() => ({}));
      const name = cleanName(b.name);
      await env.DB.prepare("UPDATE users SET name = ? WHERE id = ?").bind(name, user.id).run();
      // Spots the person shares show the new name too
      await env.DB.prepare("UPDATE shared_spots SET by_name = ? WHERE user_id = ?").bind(name || null, user.id).run();
      return reply({ user: publicUser({ ...user, name }) });
    }
    if (request.method === "DELETE") {
      if (user.refresh_token) await revoke(env, user.refresh_token).catch(e => console.log("Apple revoke failed:", e.message));
      await env.DB.batch([
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(user.id),
        // Their shared spots stay for the people who use them, without their name
        env.DB.prepare("UPDATE shared_spots SET by_name = NULL, user_id = NULL WHERE user_id = ?").bind(user.id),
        env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user.id),
      ]);
      return reply({ ok: true });
    }
  }
  return reply({ error: "not found" }, 404);
}

/// The signed-in user for a request (Authorization: Bearer <token>), or null.
export async function currentUser(request, env) {
  const token = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (token.length < 32) return null;
  const user = await env.DB.prepare(`SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id
                                     WHERE sessions.token_hash = ?`).bind(await sha256(token)).first();
  if (!user || user.blocked) return null;
  const today = new Date().toISOString().slice(0, 10);
  if (!user.last_active?.startsWith(today)) // once a day is enough to know who's still around
    await env.DB.prepare("UPDATE users SET last_active = ? WHERE id = ?").bind(new Date().toISOString(), user.id).run();
  return user;
}

const publicUser = u => ({ id: u.id, name: u.name ?? "" });
const cleanName = n => typeof n === "string" ? n.trim().replace(/\s+/g, " ").slice(0, 40) : "";

async function signIn(request, env, reply) {
  const b = await request.json().catch(() => ({}));
  if (typeof b.identityToken !== "string") return reply({ error: "identityToken required" }, 400);
  let claims;
  try { claims = await verifyAppleToken(b.identityToken, env.APNS_TOPIC); }
  catch (e) { return reply({ error: "Apple sign-in couldn't be checked: " + e.message }, 401); }

  let user = await env.DB.prepare("SELECT * FROM users WHERE apple_sub = ?").bind(claims.sub).first();
  if (user?.blocked) return reply({ error: "this account is blocked" }, 403);
  const refresh = typeof b.authorizationCode === "string" ? await exchangeCode(env, b.authorizationCode).catch(e => {
    console.log("Apple code exchange failed:", e.message); return null; }) : null;
  const now = new Date().toISOString();
  if (!user) {
    // Apple only gives the name the first time someone signs in to the app
    user = { id: crypto.randomUUID(), apple_sub: claims.sub, name: cleanName(b.givenName), created: now };
    await env.DB.prepare("INSERT INTO users (id, apple_sub, name, created, last_active, refresh_token) VALUES (?, ?, ?, ?, ?, ?)")
      .bind(user.id, user.apple_sub, user.name, now, now, refresh).run();
  } else if (refresh) {
    await env.DB.prepare("UPDATE users SET refresh_token = ?, last_active = ? WHERE id = ?").bind(refresh, now, user.id).run();
  }
  const token = randomToken();
  await env.DB.prepare("INSERT INTO sessions (token_hash, user_id, created) VALUES (?, ?, ?)")
    .bind(await sha256(token), user.id, now).run();
  return reply({ token, user: publicUser(user) });
}

// ---- Apple's identity token: RS256, signed with one of Apple's published keys ----------------------------------

let appleKeys = null; // { at, keys }
async function verifyAppleToken(jwt, bundleID) {
  const [h, p, s] = jwt.split(".");
  if (!s) throw new Error("not a JWT");
  const header = JSON.parse(b64urlText(h)), claims = JSON.parse(b64urlText(p));
  if (claims.iss !== APPLE) throw new Error("wrong issuer");
  if (claims.aud !== bundleID) throw new Error("made for another app");
  if (claims.exp * 1000 < Date.now()) throw new Error("expired");
  if (!appleKeys || Date.now() - appleKeys.at > 6 * 3600e3 || !appleKeys.keys.some(k => k.kid === header.kid)) {
    const res = await fetch(`${APPLE}/auth/keys`);
    if (!res.ok) throw new Error("Apple's keys unavailable");
    appleKeys = { at: Date.now(), keys: (await res.json()).keys };
  }
  const jwk = appleKeys.keys.find(k => k.kid === header.kid);
  if (!jwk) throw new Error("unknown key");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlBytes(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw new Error("bad signature");
  return claims;
}

// ---- Talking to Apple with our Sign in with Apple key (for revoking at account deletion) ------------------------

async function clientSecret(env) {
  if (!env.SIWA_KEY || !env.SIWA_KEY_ID) throw new Error("SIWA_KEY isn't set");
  const der = Uint8Array.from(atob(env.SIWA_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const part = o => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const body = `${part({ alg: "ES256", kid: env.SIWA_KEY_ID })}.${part({ iss: env.APNS_TEAM_ID, iat: now, exp: now + 300,
                                                                       aud: APPLE, sub: env.APNS_TOPIC })}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(body));
  return `${body}.${b64url(new Uint8Array(sig))}`;
}

async function exchangeCode(env, code) {
  const res = await fetch(`${APPLE}/auth/token`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.APNS_TOPIC, client_secret: await clientSecret(env), code, grant_type: "authorization_code" }) });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`);
  return json.refresh_token ?? null;
}

async function revoke(env, refreshToken) {
  const res = await fetch(`${APPLE}/auth/revoke`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.APNS_TOPIC, client_secret: await clientSecret(env), token: refreshToken,
                                token_type_hint: "refresh_token" }) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}

// ---- Helpers ----------------------------------------------------------------------------------------------------

function randomToken() {
  return b64url(crypto.getRandomValues(new Uint8Array(32)));
}
export async function sha256(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return [...bytes].map(b => b.toString(16).padStart(2, "0")).join("");
}
const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
const b64urlBytes = s => { // JWTs leave out the "=" padding, which atob() here insists on
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(b64 + "=".repeat((4 - b64.length % 4) % 4)), c => c.charCodeAt(0));
};
const b64urlText = s => new TextDecoder().decode(b64urlBytes(s));
