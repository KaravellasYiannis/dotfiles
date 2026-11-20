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

function socketPath() {
  const uid = process.getuid();
  const dir = join(tmpdir(), `aimux-copilot-${uid}`);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const stat = lstatSync(dir);
  if (!stat.isDirectory() || stat.uid !== uid || (stat.mode & 0o077)) return;
  const key = createHash("sha256").update(JSON.stringify([TMUX, TMUX_PANE]));
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

async function notify() {
  const { sessionId, notification_type } = JSON.parse(readFileSync(0, "utf8"));
  if (notification_type !== "permission_prompt" || typeof sessionId !== "string" ||
      !sessionId || sessionId.length > 128) return;
  const path = socketPath();
  if (!path) return;

  // The hook can run while the extension is still starting or switching sessions.
  const deadline = Date.now() + 1500;
  while (Date.now() < deadline) {
    if (await contact(path, sessionId) === "accepted") return;
    await delay(25);
  }
}

async function claimPane(onPrompt, isClosed) {
  const path = socketPath();
  if (!path) return;
  // shortcut: one Copilot session owns the pane; aggregate if sidebar sessions need sharing.
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
  // Complete each write before starting the next (including the final clear).
  spawnSync(AIMUX_BIN || "aimux", status === "clear" ? ["clear"] : ["set", status], {
    stdio: "ignore",
    timeout: 500,
    killSignal: "SIGKILL",
  });
}

async function observe() {
  const { joinSession } = await import("@microsoft/copilot-sdk/extension");
  if (!inPane) return joinSession();

  let server, observer, promptWaiting, closed, bufferedStatus;
  const close = () => {
    if (closed) return;
    closed = true;
    observer?.close();
    // Keep the pane lease until clear finishes, even when /clear starts a new session.
    server?.close();
  };
  process.once("disconnect", close);
  process.once("exit", close);
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
    process.once(signal, () => process.exit(0));
  }

  void claimPane(() => {
    if (observer) void observer.permissionPrompt();
    else promptWaiting = true;
  }, () => closed).then(lease => {
    if (closed) return lease?.close();
    server = lease;
    if (server && bufferedStatus) write(bufferedStatus);
  }).catch(() => {});

  const session = await joinSession();
  if (closed) return;
  observer = follow(session, status => {
    if (server) write(status);
    else bufferedStatus = status;
  });
  if (promptWaiting) void observer.permissionPrompt();
}

if (process.argv[2] === "--permission-prompt") {
  if (inPane) await notify().catch(() => {});
} else {
  await observe();
}
