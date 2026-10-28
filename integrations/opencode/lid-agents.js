// Lid Agents plugin for OpenCode (installed by `agents integrate`).
//
// Lid Agents counts an agent as busy when it has a caffeinate child, which is what Claude Code
// does while it works. OpenCode has no such signal, so this plugin holds
// `caffeinate -i -w <opencode pid>` while any session is busy (or retrying) and stops it when
// they are all idle. `-w` releases the assertion even if OpenCode exits without telling us.
//
// It works under Superset and cmux too: their OpenCode setups add plugins from their own
// config dirs, which OpenCode loads in addition to ~/.config/opencode, not instead of it.
import { spawn } from "node:child_process";

// One OpenCode process can serve several projects, each loading its plugins separately
// (and this file may be loaded from two config dirs), so the busy sessions and the single
// caffeinate are per process, not per plugin instance.
const shared = (globalThis.__lidAgents ??= { busy: new Set(), holder: null, exitHooked: false });

const hold = () => {
  if (shared.holder) return;
  try {
    const child = spawn("/usr/bin/caffeinate", ["-i", "-w", String(process.pid)], { stdio: "ignore" });
    const clear = () => { if (shared.holder === child) shared.holder = null; };
    child.on("exit", clear);
    child.on("error", clear);
    shared.holder = child;
  } catch {
    shared.holder = null;
  }
};

const release = () => {
  const child = shared.holder;
  shared.holder = null;
  if (child) child.kill();
};

const sync = () => (shared.busy.size > 0 ? hold() : release());

export const LidAgentsPlugin = async () => {
  if (process.platform !== "darwin") return {};
  if (!shared.exitHooked) {
    shared.exitHooked = true;
    process.once("exit", release);
  }

  return {
    event: async ({ event }) => {
      const id = event.properties?.sessionID ?? event.properties?.info?.id;
      if (!id) return;
      switch (event.type) {
        case "session.status":
          // busy and retry both mean work is in flight
          if (event.properties?.status?.type === "idle") shared.busy.delete(id);
          else shared.busy.add(id);
          break;
        case "session.busy":
          shared.busy.add(id);
          break;
        case "session.idle":
        case "session.deleted":
          shared.busy.delete(id);
          break;
        default:
          return;
      }
      sync();
    },
  };
};
