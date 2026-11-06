import "file:/usr/share/omarchy/shell/plugins/bar/widgets" as Stock

Stock.Workspaces {
  // Global IDs, not monitor-owned blocks. Depends on Omarchy's widget internals.
  function readBlocks(text) {}
  function blockOf(id) { return 0 }
  function slotOf(id) { return id }

  function focusWorkspace(id) {
    dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }
}
