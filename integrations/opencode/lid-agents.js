// Lid Agents plugin for OpenCode (installed by `agents integrate`).
//
// Lid Agents counts an agent as busy when it has a caffeinate child, which is what Claude Code
// does while it works. OpenCode has no such signal, so this plugin holds
// `caffeinate -i -t 300 -w <opencode pid>` while any session is busy (or retrying), renews it
// every 4 minutes, and stops it when they are all idle. Like Claude Code's, it expires on its
// own: `-t` if the renewals stop, `-w` if OpenCode exits without telling us.
//
// While every busy session is waiting on a permission prompt or a question, it also writes
// ~/.cache/lid-agents/waiting/<opencode pid>, so Lid Agents counts it as "needs input" rather
// than busy. Waiting is tracked per request (two prompts in one session need two answers), and
// a session that still has work in flight keeps the whole process busy.
//
// It works under Superset and cmux too: their OpenCode setups add plugins from their own
// config dirs, which OpenCode loads in addition to ~/.config/opencode, not instead of it.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// One OpenCode process can serve several projects, each loading its plugins separately
// (and this file may be loaded from two config dirs), so the busy sessions and the single
// caffeinate are per process, not per plugin instance.
const shared = (globalThis.__lidAgents ??= { busy: new Set(), holder: null, renew: null, exitHooked: false });

// sessionID → Set of pending permission/question request IDs. A plugin from before 1.2 may have
// made `shared` (or a Set here), so replace anything that isn't a Map.
if (!(shared.waiting instanceof Map)) shared.waiting = new Map();

const WAITING_DIR = join(homedir(), ".cache", "lid-agents", "waiting");
const WAITING_FILE = join(WAITING_DIR, String(process.pid));

// Needs input only when something waits and no busy session is working: one session stuck on a
// prompt mustn't hide another that's still running.
const allWaiting = () =>
  shared.waiting.size > 0 && [...shared.busy].every((id) => shared.waiting.has(id));

// The marker exists exactly while allWaiting()
const syncWaiting = () => {
  try {
    if (allWaiting()) {
      mkdirSync(WAITING_DIR, { recursive: true });
      writeFileSync(WAITING_FILE, `${Math.floor(Date.now() / 1000)} permission\n`);
    } else {
      rmSync(WAITING_FILE, { force: true });
    }
  } catch {}
};

const HOLD_SECONDS = 300;
const RENEW_MS = 240_000;

const spawnHolder = () => {
  try {
    const child = spawn("/usr/bin/caffeinate", ["-i", "-t", String(HOLD_SECONDS), "-w", String(process.pid)], {
      stdio: "ignore",
    });
    child.unref();                       // never keep OpenCode's event loop alive
    const clear = () => { if (shared.holder === child) shared.holder = null; };
    child.on("exit", clear);
    child.on("error", clear);
    return child;
  } catch {
    return null;
  }
};

const hold = () => {
  if (!shared.holder) shared.holder = spawnHolder();
  if (!shared.renew) {
    // Start the next caffeinate before the current one's timeout, then drop the old one
    shared.renew = setInterval(() => {
      if (shared.busy.size === 0) return;
      const old = shared.holder;
      shared.holder = spawnHolder();
      if (old) old.kill();
    }, RENEW_MS);
    shared.renew.unref?.();
  }
};

const release = () => {
  if (shared.renew) { clearInterval(shared.renew); shared.renew = null; }
  const child = shared.holder;
  shared.holder = null;
  if (child) child.kill();
};

const sync = () => (shared.busy.size > 0 ? hold() : release());

export const LidAgentsPlugin = async () => {
  if (process.platform !== "darwin") return {};
  if (!shared.exitHooked) {
    shared.exitHooked = true;
    process.once("exit", () => { release(); shared.waiting.clear(); syncWaiting(); });
  }

  return {
    event: async ({ event }) => {
      const props = event.properties ?? {};
      const id = props.sessionID ?? props.info?.id;
      if (!id) return;
      // The request a permission/question event is about; without one, the event covers the session
      const request = props.permissionID ?? props.requestID ?? props.questionID ?? props.callID ?? props.id;
      switch (event.type) {
        case "session.status":
          // busy and retry both mean work is in flight; idle ends the turn and any prompt in it
          if (props.status?.type === "idle") { shared.busy.delete(id); shared.waiting.delete(id); }
          else shared.busy.add(id);
          break;
        case "session.busy":
          shared.busy.add(id);
          break;
        case "session.idle":
        case "session.deleted":
        case "session.error":
          shared.busy.delete(id);
          shared.waiting.delete(id);
          break;
        case "permission.asked":
        case "question.asked": {
          const pending = shared.waiting.get(id) ?? new Set();
          pending.add(request ?? event.type);
          shared.waiting.set(id, pending);
          break;
        }
        case "permission.replied":
        case "question.replied":
        case "question.rejected": {
          const pending = shared.waiting.get(id);
          if (pending && request !== undefined && pending.has(request)) pending.delete(request);
          else shared.waiting.delete(id);               // unknown request: the session moved on
          if (pending && pending.size === 0) shared.waiting.delete(id);
          break;
        }
        default:
          return;
      }
      sync();
      syncWaiting();
    },
  };
};
