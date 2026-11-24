import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, readFileSync, unlinkSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { follow } from "./state.mjs";

const { TMUX, TMUX_PANE, SESSION_ID, AIMUX_BIN } = process.env;
const inPane = Boolean(TMUX && /^%\d+$/.test(TMUX_PANE ?? ""));

function socketPath(sessionId) {
  const uid = process.getuid();
  const dir = join(tmpdir(), `aimux-copilot-${uid}`);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const stat = lstatSync(dir);
  if (!stat.isDirectory() || stat.uid !== uid || (stat.mode & 0o077)) return;
  const key = createHash("sha256").update(JSON.stringify([TMUX, TMUX_PANE, sessionId]));
  const path = join(dir, `${key.digest("hex").slice(0, 20)}.sock`);
  if (Buffer.byteLength(path) < 104) return path;
}

function contact(path, sessionId = "") {
  return new Promise(resolve => {
    const socket = createConnection(path);
    let result;
    socket.setTimeout(100, () => socket.destroy());
    socket.once("connect", () => {
      result = "active";
      socket.end(sessionId);
    });
    socket.once("data", () => { result = "accepted"; });
    socket.once("error", error => { result ??= error.code; });
    socket.once("close", () => resolve(result));
  });
}

async function notifySession() {
  const { sessionId, notification_type } = JSON.parse(readFileSync(0, "utf8"));
  if (notification_type !== "permission_prompt" || typeof sessionId !== "string" ||
      !sessionId || sessionId.length > 128) return;
  const path = socketPath(sessionId);
  if (!path) return;

  const deadline = Date.now() + 1500;
  while (Date.now() < deadline) {
    if (await contact(path, sessionId) === "accepted") return;
    await delay(25);
  }
}

async function claimSession(onPrompt, isClosed) {
  const path = socketPath(SESSION_ID);
  if (!path) return;
  const deadline = Date.now() + 2000;
  while (!isClosed() && Date.now() < deadline) {
    const server = createServer({ allowHalfOpen: true }, socket => {
      let id = "";
      socket.setEncoding("utf8");
      socket.setTimeout(100, () => socket.destroy());
      socket.on("error", () => {});
      socket.on("data", chunk => {
        id += chunk;
        if (id.length > 128) socket.destroy();
      });
      socket.once("end", () => {
        if (id && id === SESSION_ID) {
          socket.end("ok");
          onPrompt();
        } else {
          socket.end();
        }
      });
    });
    const error = await new Promise(resolve => {
      server.on("error", resolve);
      server.listen(path, () => resolve());
    });
    if (!error) return server.unref();
    if (error.code !== "EADDRINUSE") return;

    // A crashed extension can leave a socket file with no listener.
    const stale = lstatSync(path, { throwIfNoEntry: false });
    if (stale?.isSocket() && await contact(path) === "ECONNREFUSED" &&
        lstatSync(path, { throwIfNoEntry: false })?.ino === stale.ino) {
      try {
        unlinkSync(path);
      } catch (error) {
        if (error.code !== "ENOENT") return;
      }
    }
    await delay(25);
  }
}

function write(status) {
  const { status: code, error, stderr } = spawnSync(AIMUX_BIN || "aimux", ["session", SESSION_ID, status], {
    stdio: ["ignore", "ignore", "pipe"],
    encoding: "utf8",
    timeout: 500,
    killSignal: "SIGKILL",
  });
  if (code !== 0) return error?.message || stderr?.trim() || `exit status ${code}`;
}

function parentOf(pid) {
  try {
    return Number(readFileSync(`/proc/${pid}/status`, "utf8").match(/^PPid:\s+(\d+)$/m)?.[1]);
  } catch {}
}

async function observe() {
  const { joinSession } = await import("@microsoft/copilot-sdk/extension");
  if (!inPane || !SESSION_ID || SESSION_ID.length > 128) return joinSession();

  let lease, observer, promptWaiting, closed, desired, retry, watchdog;
  const publish = () => {
    if (!lease || !desired || closed) return;
    const failure = write(desired);
    if (failure && !retry) console.error(`aimux: status update failed; retrying: ${failure}`);
    clearTimeout(retry);
    retry = failure ? setTimeout(publish, 500).unref() : undefined;
  };
  const close = () => {
    if (closed) return;
    closed = true;
    clearInterval(watchdog);
    clearTimeout(retry);
    if (observer) {
      observer.stop();
      const failure = lease && write("clear");
      if (failure) console.error(`aimux: could not clear session status: ${failure}`);
    }
    lease?.close();
  };
  process.once("disconnect", close);
  process.once("exit", close);
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
    process.once(signal, () => process.exit(0));
  }

  // On Linux the npm launcher can be killed while its runtime and extension survive.
  const runtime = process.ppid;
  const launcher = parentOf(runtime);
  if (launcher) {
    watchdog = setInterval(() => {
      if (process.ppid !== runtime || parentOf(runtime) !== launcher) process.exit(0);
    }, 250).unref();
  }

  void claimSession(() => {
    if (observer) void observer.permissionPrompt();
    else promptWaiting = true;
  }, () => closed).then(claimed => {
    if (closed) return claimed?.close();
    lease = claimed;
    publish();
  }).catch(() => {});

  const session = await joinSession();
  if (closed) return;
  observer = follow(session, status => {
    desired = status;
    publish();
  }, close);
  if (promptWaiting) void observer.permissionPrompt();
}

if (process.argv[2] === "--permission-prompt") {
  if (inPane) await notifySession().catch(() => {});
} else {
  await observe();
}
