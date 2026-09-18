// FlexFox v7.0.1 required
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);
user_pref("sidebar.visibility", "always-show");

// Keep keyboard toggles working. Do not lock hide/lock prefs in about:config.
user_pref("uc.flex.disable-flexfox", false);
user_pref("uc.flex.fully-hide-toolbox", false);
user_pref("uc.flex.fully-hide-sidebery", false);
user_pref("uc.flex.disable-sidebery-autohide", false);

// Persist Firefox vertical tabs. user.js is reapplied on every start,
// so leaving these false was resetting the tab strip back to horizontal.
user_pref("sidebar.revamp", true);
user_pref("sidebar.verticalTabs", true);

// CSS :has()
user_pref("layout.css.has-selector.enabled", true);

// Keep the previous ShyFox new-tab wallpapers instead of Firefox's built-in ones
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.enabled", false);

// Urlbar extras kept from previous user.js
user_pref("browser.urlbar.suggest.calculator", true);
user_pref("browser.urlbar.unitConversion.enabled", true);
user_pref("browser.urlbar.trimHttps", true);
user_pref("browser.urlbar.trimURLs", true);

// GTK extras kept from previous user.js
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
user_pref("widget.gtk.ignore-bogus-leave-notify", 1);
