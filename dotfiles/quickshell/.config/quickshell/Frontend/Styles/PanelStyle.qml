pragma Singleton
import QtQuick
import qs.Backend.Config

// Single shared stylesheet consumed uniformly by all panels & Settings overlay.
// Matches Launcher design tokens + keeps Bar-style 0.85 translucent fallback for compositor blur.
QtObject {
  id: root

  readonly property color _rawBackground: ThemeStore.composedFrom(
    ["panels.background", "popups.background"],
    ["panels.background-alpha", "popups.background-alpha"],
    ThemeStore.background, 1.0
  )
  readonly property color background: _rawBackground.a < 0.999
    ? _rawBackground
    : Util.alpha(_rawBackground, 0.85)
  readonly property color _darkBase: Qt.darker(ThemeStore.background, 1.35)
  readonly property color darkBackground: Qt.rgba(
    _darkBase.r, _darkBase.g, _darkBase.b,
    Math.min(0.92, Math.max(0.75, background.a))
  )

  readonly property color foreground: ThemeStore.colorFrom(["panels.text", "popups.text"], ThemeStore.foreground)
  readonly property color lightForeground: Qt.lighter(foreground, 1.18)
  readonly property color mutedText: ThemeStore.colorFrom(["panels.muted-text"], Util.alpha(foreground, 0.65))
  readonly property color subtleText: ThemeStore.colorFrom(["panels.subtle-text"], Util.alpha(foreground, 0.72))
  readonly property color accent: ThemeStore.colorFrom(["panels.accent"], ThemeStore.accent)
  readonly property color urgent: ThemeStore.colorFrom(["panels.urgent"], ThemeStore.urgent)
  readonly property color border: ThemeStore.composedFrom(
    ["panels.border", "popups.border"],
    ["panels.border-alpha", "popups.border-alpha"],
    ThemeStore.accent, 1.0
  )

  readonly property color selectionFill: Qt.rgba(accent.r, accent.g, accent.b, 0.24)
  readonly property color activeFill: Qt.rgba(accent.r, accent.g, accent.b, 0.12)
  readonly property color subtleBorder: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
  readonly property color trackFill: Util.alpha(foreground, 0.14)

  readonly property int cornerRadius: Math.max(0, ThemeStore.valInt(["panels.border-radius", "popups.border-radius"], Style.cornerRadius))
  readonly property int padding: Math.max(4, ThemeStore.valInt(["panels.padding"], Style.space(12)))
  readonly property int maxContentHeight: Math.max(200, ThemeStore.valInt(["panels.max-height"], Style.space(520)))

  readonly property string fontFamily: ThemeStore.valStr(["panels.font-family", "popups.font-family", "font.panels-family"], Style.font.family)
  readonly property int displayLargeSize: Style.font.displayLarge
  readonly property int displaySize: Style.font.display
  readonly property int headingSize: Math.max(8, ThemeStore.valInt(["panels.heading-size"], Style.font.heading))
  readonly property int titleSize: Math.max(8, ThemeStore.valInt(["panels.title-size"], Style.font.title))
  readonly property int subtitleSize: Math.max(8, ThemeStore.valInt(["panels.subtitle-size"], Style.font.subtitle))
  readonly property int bodySize: Math.max(8, ThemeStore.valInt(["panels.body-size"], Style.font.body))
  readonly property int smallSize: Math.max(8, ThemeStore.valInt(["panels.small-size"], Style.font.bodySmall))
  readonly property int captionSize: Math.max(8, ThemeStore.valInt(["panels.caption-size"], Style.font.caption))

  readonly property int openAnimMs: 220
  readonly property int closeAnimMs: 160
  readonly property int hoverColorAnimMs: 80
}
