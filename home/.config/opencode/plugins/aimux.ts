import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { Plugin } from '@opencode/plugin'

const run = promisify(execFile)

export default {
  id: 'aimux',
  async setup(ctx: Plugin.Context) {
    type Status = 'working' | 'blocked' | 'idle' | 'done'

    let queue = Promise.resolve()
    let previousStatus: Status | undefined
    const sessions = new Map<string, string>()
    const pending = new Map<string, string>()

    const report = (status: Status) => {
      queue = queue.then(async () => {
        if (status === previousStatus) return
        try {
          await run('aimux', ['set', status])
        } catch {
          return
        }
        previousStatus = status
      })
      return queue
    }

    const refresh = () => {
      if (pending.size) return report('blocked')
      if ([...sessions.values()].some((status) => status === 'busy' || status === 'retry')) return report('working')
      return report(sessions.size ? 'done' : 'idle')
    }

    await report('idle')

    const controller = new AbortController()
    const subscription = (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        switch (event.type) {
          case 'session.status': {
            sessions.set(event.data.sessionID, event.data.status.type)
            await refresh()
            break
          }
          case 'permission.asked': {
            if (!sessions.has(event.data.sessionID)) sessions.set(event.data.sessionID, 'busy')
            pending.set(`permission:${event.data.id}`, event.data.sessionID)
            await refresh()
            break
          }
          case 'permission.replied': {
            pending.delete(`permission:${event.data.requestID}`)
            await refresh()
            break
          }
          case 'form.created': {
            const { id, sessionID } = event.data.form
            if (!sessions.has(sessionID)) sessions.set(sessionID, 'busy')
            pending.set(`form:${id}`, sessionID)
            await refresh()
            break
          }
          case 'form.replied':
          case 'form.cancelled': {
            pending.delete(`form:${event.data.id}`)
            await refresh()
            break
          }
          case 'session.deleted': {
            const { sessionID } = event.data
            sessions.delete(sessionID)
            for (const [requestID, owner] of pending) {
              if (owner === sessionID) pending.delete(requestID)
            }
            await refresh()
            break
          }
        }
      }
    })().catch((error) => {
      if (!controller.signal.aborted) console.error('aimux event subscription failed', error)
    })

    return async () => {
      controller.abort()
      await subscription
      await queue
      try {
        await run('aimux', ['clear'])
      } catch {}
    }
  },
}
