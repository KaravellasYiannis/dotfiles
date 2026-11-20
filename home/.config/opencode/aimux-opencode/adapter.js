const routePollMs = 250
const retryMs = 2000
const pendingPollMs = 5000

export function trackPane({ data, ui }, runAimux) {
  const sessions = data.session
  const families = new Map()
  const deleted = new Set()
  let visible
  let hadActivity = false
  let connection = 0
  let closed = false
  let desired = "idle"
  let reported
  let writing
  let retryAt = 0

  function write() {
    if (closed || writing || desired === reported || Date.now() < retryAt) return
    const next = desired
    writing = runAimux(["set", next]).then((ok) => {
      if (ok) reported = next
      else if (desired === next) retryAt = Date.now() + retryMs
    }).finally(() => {
      writing = undefined
      if (desired !== next) write()
    })
  }

  function track(family, id) {
    if (deleted.has(id)) return
    if (!family.members.has(id)) family.members.set(id, { pending: new Set(), settled: new Set(), refreshAt: 0 })
    return family.members.get(id)
  }

  function captureRoute() {
    // The TUI can learn the parent of a resumed child after the route has opened.
    for (const [root, family] of families) {
      const resolved = sessions.root(root)
      if (resolved === root) continue
      const target = families.get(resolved) ?? family
      for (const [id, member] of family.members) {
        if (!target.members.has(id)) target.members.set(id, member)
      }
      target.active ||= family.active
      families.delete(root)
      families.set(resolved, target)
      if (visible === root) visible = resolved
    }

    const route = ui.router.current()
    let root
    if (route.type === "session" && route.sessionID !== "dummy" && !deleted.has(route.sessionID)) {
      const resolved = sessions.root(route.sessionID)
      if (!deleted.has(resolved)) root = resolved
    }

    // Tabs are shared across clients. Only this terminal's route admits a root.
    if (visible !== root && !families.get(visible)?.active) families.delete(visible)
    visible = root
    if (root && !families.has(root)) families.set(root, { active: false, members: new Map() })
    if (root) track(families.get(root), route.sessionID)
    for (const [id, family] of families) {
      track(family, id)
      // shortcut: use TUI-known descendants; enumerate them via the client if full historical discovery is needed.
      for (const member of sessions.family(id)) track(family, member)
    }
  }

  function owner(id) {
    return [...families.values()].find((family) => family.members.has(id))
  }

  function remove(id) {
    deleted.add(id)
    families.delete(id)
    owner(id)?.members.delete(id)
  }

  async function refresh(id, member) {
    const generation = connection
    const asks = new Set()
    member.refresh = asks
    member.refreshAt = Infinity
    try {
      // Use TUI data sync, which follows managed service reconnects.
      const pending = await Promise.all(["permission", "form"].map(async (kind) => {
        const source = sessions[kind]
        source.invalidate(id)
        await source.sync(id)
        return (source.list(id) ?? []).map((request) => `${kind}:${request.id}`)
      }))
      if (closed || generation !== connection || owner(id)?.members.get(id) !== member) return
      // A snapshot can race asks/replies delivered on the event stream.
      member.pending = new Set([...pending.flat(), ...asks].filter((key) => !member.settled.has(key)))
      if (member.pending.size) member.refreshAt = Math.min(member.refreshAt, Date.now() + pendingPollMs)
    } catch (error) {
      if (closed || generation !== connection || owner(id)?.members.get(id) !== member) return
      if (error?._tag === "SessionNotFoundError" && error.sessionID === id) remove(id)
      else member.refreshAt = Date.now() + retryMs
    } finally {
      member.refresh = undefined
      if (!closed) tick()
    }
  }

  function publish() {
    let blocked = false
    let running = false
    for (const [root, family] of families) {
      family.active = false
      for (const [id, member] of family.members) {
        const busy = sessions.status(id) === "running"
        const waiting = member.pending.size > 0
        family.active ||= busy || waiting
        blocked ||= waiting
        running ||= busy
      }
      if (root !== visible && !family.active) {
        families.delete(root)
        continue
      }
      for (const [id, member] of family.members) {
        if (!member.refresh && member.refreshAt <= Date.now()) void refresh(id, member)
      }
    }
    hadActivity ||= blocked || running
    const next = blocked ? "blocked" : running ? "working" : hadActivity ? "done" : "idle"
    if (desired !== next) retryAt = 0
    desired = next
    write()
  }

  function tick() {
    captureRoute()
    publish()
  }

  const stop = data.listen(({ details: event }) => {
    const { type, data: eventData } = event
    if (!/^(server\.connected|session\.(created|deleted|execution\..+)|permission\.(asked|replied)|form\.(created|replied|cancelled))$/.test(type)) return
    captureRoute()

    if (type === "server.connected") {
      connection++
      for (const family of families.values()) {
        for (const member of family.members.values()) member.refreshAt = 0
      }
    } else if (type === "session.created") {
      deleted.delete(eventData.sessionID)
      const family = owner(eventData.parentID)
      if (family) track(family, eventData.sessionID)
    } else {
      const id = type === "form.created" ? eventData.form.sessionID : eventData.sessionID
      const member = owner(id)?.members.get(id)
      if (!member) return
      if (type === "session.deleted") {
        remove(id)
      } else if (type.startsWith("session.execution.")) {
        hadActivity = true
        // Interrupting a turn can remove a permission without a reply event.
        if (type !== "session.execution.started" && member.pending.size) member.refreshAt = 0
      } else {
        const asked = type === "permission.asked" || type === "form.created"
        const kind = type.startsWith("permission.") ? "permission" : "form"
        const request = type === "form.created" ? eventData.form.id
          : type === "permission.replied" ? eventData.requestID : eventData.id
        const key = `${kind}:${request}`
        if (asked) {
          member.settled.delete(key)
          member.pending.add(key)
          member.refresh?.add(key)
          member.refreshAt = Math.min(member.refreshAt, Date.now() + pendingPollMs)
        } else {
          member.settled.add(key)
          member.pending.delete(key)
          member.refresh?.delete(key)
        }
      }
    }
    publish()
  })

  tick()
  const timer = setInterval(tick, routePollMs)
  return async () => {
    closed = true
    clearInterval(timer)
    stop()
    await writing
    await runAimux(["clear"])
  }
}
