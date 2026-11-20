import { execFile } from "node:child_process"
import { Plugin } from "@opencode/plugin/tui"
import { trackPane } from "./adapter.js"

export default Plugin.define({
  id: "aimux.status",
  setup(context) {
    const { TMUX, TMUX_PANE, AIMUX_BIN } = process.env
    if (!TMUX || !/^%\d+$/.test(TMUX_PANE ?? "")) return

    const env = { ...process.env, TMUX, TMUX_PANE }
    return trackPane(context, (args) => new Promise((resolve) => {
      execFile(AIMUX_BIN || "aimux", args, { env, timeout: 2000 }, (error) => resolve(!error))
    }))
  },
})
