// lid-agents.liam-is-an.ai: landing page plus stable download links for Lid Agents.
//
//   /                 landing page (latest version read from GitHub, cached 10 min)
//   /download, /dmg   → latest notarized LidAgents.dmg
//   /install.sh       → latest installer, for `curl -fsSL …/install.sh | bash`
//   /github           → the repo
//
// Releases are published by GitHub Actions; nothing here needs redeploying when one ships.

import icon from "./icon.png";

const REPO = "liam-machine/lid-agents";
const LATEST = `https://github.com/${REPO}/releases/latest/download`;
const REDIRECTS = {
  "/download": `${LATEST}/LidAgents.dmg`,
  "/dmg": `${LATEST}/LidAgents.dmg`,
  "/LidAgents.dmg": `${LATEST}/LidAgents.dmg`,
  "/install.sh": `${LATEST}/install.sh`,
  "/install": `${LATEST}/install.sh`,
  "/github": `https://github.com/${REPO}`,
  "/releases": `https://github.com/${REPO}/releases`,
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (REDIRECTS[path]) return Response.redirect(REDIRECTS[path], 302);
    if (path === "/icon.png" || path === "/favicon.ico") {
      return new Response(icon, {
        headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" },
      });
    }
    if (path !== "/") return Response.redirect(`${url.origin}/`, 302);

    const version = await latestVersion();
    return new Response(page(version, url.origin), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300",
        "content-security-policy": "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
        "x-content-type-options": "nosniff",
        "referrer-policy": "strict-origin-when-cross-origin",
      },
    });
  },
};

async function latestVersion() {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { "user-agent": "lid-agents-site", accept: "application/vnd.github+json" },
      cf: { cacheTtl: 600, cacheEverything: true },
    });
    if (!res.ok) return "";
    const tag = (await res.json()).tag_name || "";
    return /^v?\d+(\.\d+){1,3}$/.test(tag) ? tag.replace(/^v/, "") : "";
  } catch {
    return "";
  }
}

function page(version, origin) {
  const install = `curl -fsSL ${origin}/install.sh | bash`;
  const meta = version ? `Version ${version} · ` : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lid Agents</title>
<meta name="description" content="Close your MacBook's lid and let your AI agents keep working. A free menu bar app for macOS.">
<meta property="og:title" content="Lid Agents">
<meta property="og:description" content="Close your MacBook's lid and let your AI agents keep working.">
<meta property="og:image" content="${origin}/icon.png">
<link rel="icon" href="/icon.png">
<style>
  :root {
    --bg: #faf6f1; --surface: #ffffff; --text: #2b1d12; --muted: #7a6656; --line: #eadfd3;
    --accent: #8a5a2b; --accent-strong: #6b4220; --accent-text: #ffffff; --code: #f3ece4;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #17110c; --surface: #211811; --text: #f4ebe1; --muted: #b29f8d; --line: #3a2c20;
      --accent: #c98b4f; --accent-strong: #dba06a; --accent-text: #1a120b; --code: #2a1f16;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 17px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif; }
  main { max-width: 680px; margin: 0 auto; padding: 64px 16px 48px; }
  .hero { text-align: center; }
  .hero img { width: 112px; height: 112px; }
  h1 { font-size: 40px; line-height: 1.1; margin: 18px 0 10px; letter-spacing: -0.02em; }
  .tagline { font-size: 21px; color: var(--muted); margin: 0 auto 30px; max-width: 30ch; }
  .button { display: inline-flex; align-items: center; gap: 10px; background: var(--accent); color: var(--accent-text);
    text-decoration: none; font-weight: 600; font-size: 18px; padding: 14px 26px; border-radius: 12px;
    transition: background .15s; }
  .button:hover { background: var(--accent-strong); }
  .button svg { width: 18px; height: 18px; fill: currentColor; }
  .meta { color: var(--muted); font-size: 14px; margin-top: 12px; }
  .alt { margin: 40px 0 0; }
  .alt p { color: var(--muted); font-size: 15px; margin: 0 0 8px; text-align: center; }
  .cmd { display: flex; align-items: center; gap: 8px; background: var(--code); border: 1px solid var(--line);
    border-radius: 10px; padding: 10px 10px 10px 14px; }
  .cmd code { flex: 1; overflow-x: auto; white-space: nowrap; font: 14px ui-monospace, "SF Mono", Menlo, monospace; }
  .cmd button { border: 1px solid var(--line); background: var(--surface); color: var(--text); border-radius: 8px;
    font: inherit; font-size: 13px; padding: 5px 10px; cursor: pointer; flex-shrink: 0; }
  section { margin-top: 56px; }
  h2 { font-size: 22px; margin: 0 0 16px; }
  .steps { display: grid; gap: 12px; padding: 0; margin: 0; list-style: none; counter-reset: s; }
  .steps li { background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px 14px 52px;
    position: relative; counter-increment: s; }
  .steps li::before { content: counter(s); position: absolute; left: 16px; top: 14px; width: 24px; height: 24px;
    border-radius: 50%; background: var(--accent); color: var(--accent-text); font-size: 13px; font-weight: 700;
    display: grid; place-items: center; }
  .steps b { display: block; }
  .steps span { color: var(--muted); font-size: 15px; }
  .facts { color: var(--muted); font-size: 15px; padding-left: 20px; margin: 0; }
  .facts li { margin: 6px 0; }
  footer { margin-top: 56px; padding-top: 20px; border-top: 1px solid var(--line); color: var(--muted); font-size: 14px;
    display: flex; flex-wrap: wrap; gap: 8px 18px; justify-content: center; }
  a { color: var(--accent); }
  kbd { font: 13px ui-monospace, Menlo, monospace; border: 1px solid var(--line); border-bottom-width: 2px;
    border-radius: 5px; padding: 1px 5px; background: var(--surface); }
  @media (max-width: 480px) { h1 { font-size: 32px; } .tagline { font-size: 18px; } main { padding-top: 40px; } }
</style>
</head>
<body>
<main>
  <div class="hero">
    <img src="/icon.png" alt="" width="112" height="112">
    <h1>Lid Agents</h1>
    <p class="tagline">Close your MacBook's lid and let your AI agents keep working.</p>
    <a class="button" href="/download">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a1 1 0 0 1 1 1v9.59l3.3-3.3a1 1 0 1 1 1.4 1.42l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.42l3.3 3.3V4a1 1 0 0 1 1-1zM5 19h14a1 1 0 1 1 0 2H5a1 1 0 1 1 0-2z"/></svg>
      Download for macOS
    </a>
    <div class="meta">${meta}macOS 13 or later · Apple Silicon &amp; Intel · Notarized by Apple · Free</div>
  </div>

  <div class="alt">
    <p>Or install from Terminal</p>
    <div class="cmd"><code id="cmd">${install}</code><button type="button" id="copy">Copy</button></div>
  </div>

  <section>
    <h2>How it works</h2>
    <ol class="steps">
      <li><b>Click the cup in your menu bar</b><span>or press <kbd>⌃0</kbd>. It fills in and shows how many agents are busy.</span></li>
      <li><b>Close the lid</b><span>The screen goes off, and Claude Code, Codex and the rest keep running.</span></li>
      <li><b>Your agents finish</b><span>A few minutes later the cup empties and the closed Mac goes to sleep.</span></li>
    </ol>
  </section>

  <section>
    <h2>Good to know</h2>
    <ul class="facts">
      <li>It only stays awake while an agent is actually working, never because a session is open.</li>
      <li>It turns itself off after 8 hours or at 15% battery, whichever comes first.</li>
      <li>It asks for your password once, to allow a single command: <code>pmset -a disablesleep</code>.</li>
      <li>Don't put the Mac in a bag while the cup is full. It can't get rid of heat with the lid shut.</li>
    </ul>
  </section>

  <footer>
    <a href="/github">Source on GitHub</a>
    <a href="/releases">Release notes</a>
    <span>MIT licensed</span>
  </footer>
</main>
<script>
  document.getElementById("copy").addEventListener("click", async (e) => {
    try {
      await navigator.clipboard.writeText(document.getElementById("cmd").textContent);
      e.target.textContent = "Copied";
      setTimeout(() => (e.target.textContent = "Copy"), 1500);
    } catch {}
  });
</script>
</body>
</html>`;
}
