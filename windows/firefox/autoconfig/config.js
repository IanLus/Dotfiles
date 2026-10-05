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
      if (commands && typeof commands.downloadsUI === "function" && !commands._dotfilesDownloadsPanel) {
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
      }

      // Linux binds downloads to Ctrl+Shift+Y and uses Ctrl+J for the legacy
      // search bar. Point Ctrl+J at the same downloads command as Windows.
      if (Services.appinfo.OS === "Linux") {
        const doc = win.document;
        if (doc && !doc._dotfilesDownloadsCtrlJ) {
          const search = doc.getElementById("key_search2");
          if (search) {
            search.removeAttribute("data-l10n-id");
            search.removeAttribute("key");
            search.removeAttribute("keycode");
            search.removeAttribute("modifiers");
            search.removeAttribute("command");
          }
          const downloads = doc.getElementById("key_openDownloads");
          if (downloads) {
            downloads.removeAttribute("data-l10n-id");
            downloads.removeAttribute("keycode");
            downloads.setAttribute("modifiers", "accel");
            downloads.setAttribute("key", "J");
          }
          doc._dotfilesDownloadsCtrlJ = true;
        }
      }
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
