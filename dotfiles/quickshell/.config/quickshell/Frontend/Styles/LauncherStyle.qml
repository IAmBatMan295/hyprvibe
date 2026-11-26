pragma Singleton
import QtQuick
import qs.Backend.Config

// Dedicated stylesheet + preset resolver for the Launcher overlay.
// Resolves [launcher.<preset>.*] -> [launcher.*] -> [popups]/[menu]/[font]/[effects]/Style.
QtObject {
  id: root

  readonly property color _rawBg: ThemeStore.composedFrom(
    ["launcher.background", "popups.background"],
    ["launcher.background-alpha", "popups.background-alpha"],
    ThemeStore.background, 1.0
  )
  readonly property color _effBg: _rawBg.a < 0.999 ? _rawBg : Util.alpha(_rawBg, 0.85)
  readonly property color _darkBase: Qt.darker(ThemeStore.background, 1.35)

  readonly property var palette: ({
    background: _effBg,
    dark_background: Qt.rgba(_darkBase.r, _darkBase.g, _darkBase.b, Math.min(0.92, Math.max(0.75, _effBg.a))),
    lighter_background: ThemeStore.menu.selectedBackground,
    accent: ThemeStore.composedFrom(
      ["launcher.border", "popups.border"],
      ["launcher.border-alpha", "popups.border-alpha"],
      ThemeStore.accent, 1.0
    ),
    selection: ThemeStore.menu.selectedBackground.a > 0.01
      ? Qt.rgba(ThemeStore.accent.r, ThemeStore.accent.g, ThemeStore.accent.b, 0.28)
      : Style.selectionFill,
    muted: ThemeStore.muted,
    foreground: ThemeStore.colorFrom(["launcher.text", "popups.text"], ThemeStore.foreground),
    light_foreground: Qt.lighter(ThemeStore.foreground, 1.18),
    red: ThemeStore.urgent,
    yellow: ThemeStore.accent
  })

  readonly property var anchorAliases: ({
    center: "center", north: "top", top: "top", south: "bottom", bottom: "bottom",
    west: "left", left: "left", east: "right", right: "right",
    northwest: "top-left", "top-left": "top-left",
    northeast: "top-right", "top-right": "top-right",
    southwest: "bottom-left", "bottom-left": "bottom-left",
    southeast: "bottom-right", "bottom-right": "bottom-right"
  })

  readonly property var presets: ({
    drun: {
      prompt: " ", placeholder: "Search applications...",
      width: 440, lines: 7, rowHeight: 46,
      showSearch: true, showNumbers: false, showIcons: true, showSubtext: true,
      showPrompt: true, centerText: false, allowCustom: false, sort: true
    },
    clipboard: {
      prompt: " ", placeholder: "Filter clipboard history...",
      width: 620, lines: 7, rowHeight: 44,
      showSearch: true, showNumbers: true, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: false, sort: false
    },
    helpers: {
      prompt: " ", placeholder: "Select helper utility...",
      headerIcon: "",
      width: 520, lines: 6, rowHeight: 44,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: true,
      showPrompt: true, centerText: false, allowCustom: false, sort: true
    },
    power: {
      prompt: "System", placeholder: "",
      headerIcon: "",
      width: 280, lines: 4, rowHeight: 46,
      showSearch: false, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, showFooter: false, centerText: false, allowCustom: false, sort: false
    },
    profiles: {
      prompt: "Power Profile", placeholder: "",
      headerIcon: "󰓅",
      width: 300, lines: 3, rowHeight: 46,
      showSearch: false, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, showFooter: false, centerText: false, allowCustom: false, sort: false
    },
    record: {
      prompt: "Recording Profiles", placeholder: "",
      headerIcon: "",
      width: 320, lines: 2, rowHeight: 44,
      showSearch: false, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, showFooter: false, centerText: false, allowCustom: false, sort: false
    },
    theme: {
      prompt: "Theme", placeholder: "Filter themes...",
      width: 350, lines: 6, rowHeight: 44,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: true, allowCustom: false, sort: true
    },
    compact: {
      prompt: "❯", placeholder: "Type to filter...",
      width: 520, lines: 7, rowHeight: 44,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: true, sort: true
    }
  })

  function normalizeAnchor(a) {
    var key = String(a || "center").toLowerCase().trim()
    return root.anchorAliases[key] || "center"
  }

  function resolve(name, overrides) {
    var cfg = root.presets[name] || root.presets.compact
    var ov = overrides || {}
    var sec = "launcher." + name

    var animStyle = Style.effects.animations
      ? ThemeStore.valStr([sec + ".animation", "effects.launcher-animation", "launcher.animation"], "none").toLowerCase()
      : "none"

    var defaultAnchor = ThemeStore.valStr([sec + ".anchor", "launcher.anchor"], "center")
    var defaultFooter = (cfg.showFooter !== undefined) ? cfg.showFooter : ThemeStore.valBool(["launcher.show-footer"], true)
    return {
      presetName: name,
      printOnly: !!ov.printOnly,
      fontFamily: ThemeStore.valStr([sec + ".font-family", "launcher.font-family", "font.launcher-family"], Style.font.family),
      fontSize: Math.max(8, ThemeStore.valInt([sec + ".font-size", "launcher.font-size"], Style.font.subtitle)),
      borderWidth: Math.max(0, ThemeStore.valInt([sec + ".border-width", "launcher.border-width"], Math.max(3, Style.borderSize + 1))),
      borderRadius: Math.max(0, ThemeStore.valInt([sec + ".border-radius", "launcher.border-radius"], Style.cornerRadius)),
      animStyle: animStyle,
      animMs: Math.max(0, ThemeStore.valInt(["effects.launcher-animation-ms", "launcher.animation-ms"], 110)),
      prompt: ov.prompt !== undefined ? ov.prompt : ThemeStore.valStr([sec + ".prompt"], cfg.prompt),
      headerIcon: ThemeStore.valStr([sec + ".header-icon"], cfg.headerIcon || ""),
      placeholder: ov.placeholder !== undefined ? ov.placeholder : ThemeStore.valStr([sec + ".placeholder"], cfg.placeholder),
      width: ov.width > 0 ? ov.width : Math.max(180, ThemeStore.valInt([sec + ".width", "launcher.width"], cfg.width)),
      lines: ov.lines > 0 ? ov.lines : Math.max(1, ThemeStore.valInt([sec + ".lines", "launcher.lines"], cfg.lines)),
      rowHeight: Math.max(24, ThemeStore.valInt([sec + ".row-height", "launcher.row-height"], cfg.rowHeight)),
      showSearch: ov.showSearch !== undefined ? !!ov.showSearch : ThemeStore.valBool([sec + ".show-search"], cfg.showSearch),
      showNumbers: ov.showNumbers !== undefined ? !!ov.showNumbers : ThemeStore.valBool([sec + ".show-numbers"], cfg.showNumbers),
      showIcons: ov.showIcons !== undefined ? !!ov.showIcons : ThemeStore.valBool([sec + ".show-icons"], cfg.showIcons),
      showSubtext: ThemeStore.valBool([sec + ".show-subtext"], cfg.showSubtext),
      showPrompt: ThemeStore.valBool([sec + ".show-prompt"], cfg.showPrompt),
      showFooter: ov.showFooter !== undefined ? !!ov.showFooter : ThemeStore.valBool([sec + ".show-footer"], defaultFooter),
      dynamicHeight: ThemeStore.valBool([sec + ".dynamic-height", "launcher.dynamic-height"], false),
      centerText: ov.align === "center" ? true : (ov.align === "left" ? false : ThemeStore.valBool([sec + ".center-text"], cfg.centerText)),
      allowCustomInput: !!ov.dmenu || cfg.allowCustom,
      onlyMatch: !!ov.onlyMatch,
      resultFormat: ov.format !== undefined ? String(ov.format) : "s",
      benchAutoAck: !!ov.benchAutoAck,
      anchor: ov.anchor !== undefined ? root.normalizeAnchor(String(ov.anchor)) : root.normalizeAnchor(defaultAnchor),
      xOffset: ov.xOffset !== undefined ? Number(ov.xOffset) : ThemeStore.valInt([sec + ".x-offset", "launcher.x-offset"], 0),
      yOffset: ov.yOffset !== undefined ? Number(ov.yOffset) : ThemeStore.valInt([sec + ".y-offset", "launcher.y-offset"], 0),
      margin: (ov.margin !== undefined && Number(ov.margin) >= 0) ? Number(ov.margin) : Math.max(0, ThemeStore.valInt([sec + ".margin", "launcher.margin"], 16)),
      matchingMode: ov.matching !== undefined ? String(ov.matching) : ThemeStore.valStr([sec + ".matching", "launcher.matching"], "fuzzy"),
      caseSensitive: ov.caseSensitive !== undefined ? !!ov.caseSensitive : ThemeStore.valBool([sec + ".case-sensitive", "launcher.case-sensitive"], false),
      sortEnabled: ov.sort !== undefined ? !!ov.sort : ThemeStore.valBool([sec + ".sort", "launcher.sort"], cfg.sort)
    }
  }
}
