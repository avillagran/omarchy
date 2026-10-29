pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Plural.js" as Plural
import "Numbers.js" as Numbers
import "I18nModel.js" as Model
import "I18nSystem.js" as System

// Display-language strings for the shell. The selected code lives in
// ~/.config/omarchy/language (omarchy-language owns it); a missing file
// means English. Strings come from default/i18n/<code>/shell.json layered
// over the English catalog, so a missing translation falls back to English
// per string. Use as I18n.t("common.search"), with .arg(...) for %1 holes,
// and I18n.tn(key, count).arg(I18n.formatNumber(count)) for an
// entry with plural forms.
// The language file is watched, so switching language under Setup
// re-renders the shell without a restart.
QtObject {
  id: root

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

  readonly property string language: languageCode(languageFile.text())
  readonly property var localeSettings: parseCatalog(registryFile.text())[root.language] || ({})
  readonly property string formatLocale: localeSettings.formatLocale || "en-US"
  // From the registry: how numbers are written and which way text runs.
  readonly property string decimal: localeSettings.decimal || "."
  readonly property string zeroDigit: localeSettings.zeroDigit || "0"
  readonly property bool rightToLeft: localeSettings.direction === "rtl"

  // Reading text() makes blockLoading take effect on the first lookup.
  // These bindings also rebuild the maps when a watched catalog changes.
  readonly property var englishStrings: parseCatalog(englishCatalogFile.text())
  readonly property var languageStrings: parseCatalog(languageCatalogFile.text())
  readonly property var strings: {
    var merged = ({})
    for (var k in root.englishStrings) merged[k] = root.englishStrings[k]
    for (var k2 in root.languageStrings) merged[k2] = root.languageStrings[k2]
    return merged
  }

  // The optional fallback is what imperative callers (the JS models) pass
  // as their English text: for a key the catalogs do not carry, they keep
  // sensible English instead of a raw key.
  function t(key, fallback) {
    var value = root.strings[key]
    if (value && typeof value === "object") value = value.other
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  // The form of a plural entry for count, by the language's plural rules
  // (Plural.js). The English entry answers when the translation has none.
  function tn(key, count, fallback) {
    var value = Plural.pick(root.languageStrings[key], root.language, count)
    if (typeof value !== "string" || value.length === 0) value = Plural.pick(root.englishStrings[key], "en", count)
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  // A number with the language's decimal separator and digits, ungrouped:
  // formatNumber(13.14, 1) is "13,1" in Danish. Pass decimals to round;
  // without them the value is written as it is.
  function formatNumber(value, decimals) {
    return Numbers.format(value, decimals, root.decimal, root.zeroDigit)
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function languageCode(raw) {
    var code = String(raw || "").trim()
    if (!/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)) code = "en"
    return code
  }

  // The catalogs are small local files, read synchronously so the first
  // binding to call t() already gets the string rather than the raw key.
  property FileView languageFile: FileView {
    // OMARCHY_LANGUAGE_FILE overrides the location, as it does for
    // omarchy-i18n, so tests can pin a language whatever the machine uses.
    path: Quickshell.env("OMARCHY_LANGUAGE_FILE") || (root.configHome + "/omarchy/language")
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView englishCatalogFile: FileView {
    path: root.omarchyPath + "/default/i18n/en/shell.json"
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView languageCatalogFile: FileView {
    path: root.omarchyPath + "/default/i18n/" + root.language + "/shell.json"
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView registryFile: FileView {
    path: root.omarchyPath + "/default/i18n/locales.json"
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  // Runtime translation by source string (tr, trc, ntr), for labels the
  // Ui kit renders on behalf of plugins.

  // ---------------------------------------------------------------------
  // Locale

  readonly property var candidates: Model.localeCandidates({
    LANGUAGE: Quickshell.env("LANGUAGE"),
    LC_ALL: Quickshell.env("LC_ALL"),
    LC_MESSAGES: Quickshell.env("LC_MESSAGES"),
    LANG: Quickshell.env("LANG")
  })

  // Primary gettext language code ("ca" for ca_ES, or the first LANGUAGE
  // entry). Empty means English / C: nothing to translate and no cache to
  // keep. Distinct from language above, the code picked under Setup.
  readonly property string gettextLanguage: candidates.length > 0 ? candidates[0].split("_")[0] : ""

  // Where a pack's locale sits in the user's preference order, for use as
  // its registration precedence. -1 means the pack does not apply.
  function precedenceFor(locale) {
    var normalized = Model.normalizeLocale(locale)
    if (!normalized) return -1
    var index = candidates.indexOf(normalized)
    if (index === -1) index = candidates.indexOf(normalized.split("_")[0])
    return index
  }

  // ---------------------------------------------------------------------
  // Lookup

  // Bumped on every registry change. Read inside every lookup so QML
  // bindings that call tr() depend on it and repaint when catalogs change.
  property int revision: 0
  property var _registry: Model.createRegistry()

  function _lookup(source, options) {
    void root.revision
    return root._registry.translate(source, options)
  }

  function _lookupPlural(count, singular, plural, options) {
    void root.revision
    return root._registry.translatePlural(count, singular, plural, options)
  }

  function tr(source, args) {
    return _lookup(source, { args: args })
  }

  function trc(context, source, args) {
    return _lookup(source, { context: context, args: args })
  }

  function ntr(count, singular, plural, args) {
    return _lookupPlural(count, singular, plural, { args: args })
  }

  // Marks a string for extraction without translating it, for strings
  // defined away from where they are shown (a model returning a status).
  function noop(source) {
    return source
  }

  // A translator bound to one domain: lookups walk the domain, its
  // clonedFrom parents, then the global merge.
  function domain(id) {
    var d = String(id === undefined || id === null ? "" : id)
    return {
      id: d,
      tr: function(source, args) {
        return root._lookup(source, { domain: d, args: args })
      },
      trc: function(context, source, args) {
        return root._lookup(source, { domain: d, context: context, args: args })
      },
      ntr: function(count, singular, plural, args) {
        return root._lookupPlural(count, singular, plural, { domain: d, args: args })
      },
      noop: function(source) { return source }
    }
  }

  // ---------------------------------------------------------------------
  // Registration

  // Replace an owner's whole contribution atomically.
  //   catalogs  { domain: catalog }   one po2json-shaped object per domain
  //   options   { links: { childDomain: parentDomain }, precedence: int }
  function setCatalogs(ownerId, catalogs, options) {
    var result = root._registry.setCatalogs(String(ownerId), catalogs, options)
    root._changed()
    return result
  }

  function clearCatalogs(ownerId) {
    var removed = root._registry.clearOwner(String(ownerId))
    if (removed) root._changed()
    return removed
  }

  function _changed() {
    root.revision = root._registry.revision()
    root.cacheWriteTimer.restart()
  }

  // ---------------------------------------------------------------------
  // System gettext catalogs
  //
  // Runs once at startup: for the first candidate locale that has any of
  // the well-known desktop domains, msgunfmt concatenates them into PO
  // text, which I18nSystem.js folds into one catalog. Registered below the
  // plugin i18n.json source so an author can still override a string.
  // The merge is persisted into the startup snapshot, so subsequent logins
  // render translated on the first frame and this process only refreshes.

  readonly property var systemDomains: ["gtk30", "gtk40", "glib20", "gdk-pixbuf", "gnome-desktop-3.0"]

  function _systemCatalogCommand() {
    var candidates = []
    for (var i = 0; i < root.candidates.length; i++) {
      // /usr/share/locale directories never carry an encoding suffix.
      var bare = String(root.candidates[i]).replace(/\..*$/, "")
      if (bare && candidates.indexOf(bare) === -1) candidates.push(bare)
    }
    if (candidates.length === 0) return []

    var script = ""
      + "DOMAINS=\"" + root.systemDomains.join(" ") + "\"\n"
      + "for loc in " + candidates.join(" ") + "; do\n"
      + "  files=\"\"\n"
      + "  for d in $DOMAINS; do\n"
      + "    f=\"/usr/share/locale/$loc/LC_MESSAGES/$d.mo\"\n"
      + "    [ -f \"$f\" ] && files=\"$files '$f'\"\n"
      + "  done\n"
      + "  if [ -n \"$files\" ]; then\n"
      + "    echo \"X-OMARCHY-SYSTEM-LOCALE: $loc\"\n"
      + "    eval msgunfmt --no-wrap $files\n"
      + "    exit 0\n"
      + "  fi\n"
      + "done\n"
      + "exit 1\n"
    return ["bash", "-c", script]
  }

  property Process systemCatalogProcess: Process {
    command: root._systemCatalogCommand()
    running: true
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var output = systemCatalogStdout.text || ""
      var marker = output.indexOf("\n")
      if (marker === -1) return
      var catalog = System.buildCatalog([output.slice(marker + 1)])
      var keys = Object.keys(catalog).length
      if (keys > 0) {
        console.log("I18n: system gettext catalog for " + root.candidates.join(", ")
          + " (" + (keys - (catalog[""] ? 1 : 0)) + " entries)")
        root.setCatalogs("system:gettext", ({ "omarchy.system": catalog }), { precedence: 200 })
      }
    }
    stdout: StdioCollector {
      id: systemCatalogStdout
      waitForEnd: true
    }
  }

  // ---------------------------------------------------------------------
  // Startup cache

  readonly property string cacheDir: {
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    var base = xdg ? String(xdg) : String(Quickshell.env("HOME")) + "/.cache"
    return base.replace(/\/$/, "") + "/omarchy/i18n"
  }
  readonly property string cachePath: gettextLanguage ? cacheDir + "/" + gettextLanguage + ".json" : ""

  property FileView cacheFile: FileView {
    path: root.cachePath
    // Synchronous on purpose: the whole point is having catalogs before the
    // bar's first frame. The file is small and local.
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root._loadCache(text())
    // No cache yet, or unreadable: English until a pack registers.
    onLoadFailed: function(error) { }
  }

  function _loadCache(raw) {
    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (root._registry.loadSnapshot(parsed)) root.revision = root._registry.revision()
    } catch (error) {
      console.warn("I18n: ignoring unreadable cache at " + root.cachePath + ": " + error)
    }
  }

  // Registrations arrive in bursts (one pack per locale, a rescan); coalesce
  // them into one write.
  property Timer cacheWriteTimer: Timer {
    interval: 250
    repeat: false
    onTriggered: root._writeCache()
  }

  function _writeCache() {
    if (!root.cachePath) return
    var snapshot = root._registry.snapshot()
    root.cacheFile.setText(JSON.stringify(snapshot) + "\n")
  }
}
