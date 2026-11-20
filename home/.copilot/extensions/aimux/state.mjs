export function follow(session, write) {
  let phase = "idle";
  let published, closed;
  let permissions = new Set();
  const questions = new Set();
  let completedDuringRead, readAgain;

  function publish() {
    const status = permissions.size || questions.size ? "blocked" : phase;
    if (status !== published) {
      published = status;
      write(status);
    }
  }

  function close() {
    if (closed) return;
    closed = true;
    unsubscribe();
    write("clear");
  }

  async function permissionPrompt() {
    if (closed) return;
    if (completedDuringRead) {
      readAgain = true;
      return;
    }
    do {
      readAgain = false;
      completedDuringRead = new Set();
      try {
        // The CLI's notification confirms a real dialog but contains no request ID.
        // Query only pending prompts, not the transcript or the pre-evaluation permission hook.
        const { items } = await session.rpc.permissions.pendingRequests();
        if (!closed) {
          permissions = new Set(items.map(item => item.requestId)
            .filter(id => id && !completedDuringRead.has(id)));
          publish();
        }
      } catch {}
    } while (!closed && readAgain);
    completedDuringRead = undefined;
  }

  const unsubscribe = session.on(({ type, data, agentId, checkpoint }) => {
    if (closed || checkpoint) return;
    const id = data?.requestId;
    switch (type) {
      case "assistant.turn_start":
        if (!agentId) phase = "working";
        break;
      case "session.idle":
        // The runtime can go idle between Autopilot continuations.
        if (!agentId && phase === "working" && (data?.mode !== "autopilot" || data.aborted)) {
          phase = "done";
        }
        break;
      case "session.autopilot_stopped":
        if (!agentId && phase === "working") phase = "done";
        break;
      case "session.shutdown":
        close();
        return;
      case "permission.completed":
        completedDuringRead?.add(id);
        permissions.delete(id);
        break;
      case "user_input.requested":
      case "elicitation.requested":
        if (id) questions.add(`${type}:${id}`);
        break;
      case "user_input.completed":
        questions.delete(`user_input.requested:${id}`);
        break;
      case "elicitation.completed":
        questions.delete(`elicitation.requested:${id}`);
        break;
      default:
        return;
    }
    publish();
  });

  publish();
  return { permissionPrompt, close };
}
