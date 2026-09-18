// skip 1st line
// Make Ctrl+J open the toolbar downloads panel instead of the Library window.
try {
  const { Services } = globalThis;

  function patchDownloadsShortcut(win) {
    try {
      if (!win || win.closed) {
        return;
      }
      const commands = win.BrowserCommands;
      if (!commands || typeof commands.downloadsUI !== "function") {
        return;
      }
      if (commands._dotfilesDownloadsPanel) {
        return;
      }

      const original = commands.downloadsUI.bind(commands);
      commands.downloadsUI = function downloadsUI() {
        try {
          const panel = win.DownloadsPanel;
          if (!panel || typeof panel.showPanel !== "function") {
            original();
            return;
          }
          const showing =
            panel.isPanelShowing ||
            (panel.panel && panel.panel.state && panel.panel.state !== "closed");
          if (showing) {
            panel.hidePanel();
            return;
          }
          panel.showPanel(true, true);
        } catch (ex) {
          original();
        }
      };
      commands._dotfilesDownloadsPanel = true;
    } catch (ex) {}
  }

  const observer = {
    observe(win, topic) {
      if (topic === "browser-delayed-startup-finished") {
        patchDownloadsShortcut(win);
      }
    },
  };

  if (!Services.appinfo.inSafeMode) {
    Services.obs.addObserver(observer, "browser-delayed-startup-finished");
  }
} catch (ex) {}
