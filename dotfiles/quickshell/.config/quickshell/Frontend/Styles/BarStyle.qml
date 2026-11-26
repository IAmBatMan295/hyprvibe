pragma Singleton
import QtQuick
import qs.Backend.Config

// Dedicated stylesheet for the status bar, bar icons, and modular bar widgets.
QtObject {
  id: root

  readonly property color background: ThemeStore.bar.background
  readonly property color foreground: ThemeStore.bar.text
  readonly property color active: ThemeStore.bar.active
  readonly property color accent: ThemeStore.accent
  readonly property color muted: ThemeStore.muted
  readonly property color urgent: ThemeStore.urgent

  readonly property string fontFamily: ThemeStore.valStr(["bar.font-family", "font.bar-family"], Style.font.family)
  readonly property int fontSize: Math.max(8, ThemeStore.valInt(["bar.font-size"], Style.font.body))
  readonly property int cornerRadius: Math.max(0, ThemeStore.valInt(["bar.border-radius"], Style.cornerRadius))

  readonly property int sizeHorizontal: Style.bar.sizeHorizontal
  readonly property int sizeVertical: Style.bar.sizeVertical
  readonly property int iconSlot: Style.bar.iconSlot
  readonly property int iconCanvas: Style.bar.iconCanvas
  readonly property int iconFont: Style.bar.iconFont
  readonly property int statusSlot: Style.bar.statusSlot

  readonly property int foregroundFadeMs: 420
  readonly property int slideAnimMs: 220

  readonly property string cpuStyle: Style.barWidgetStyle("cpu", "text")
  readonly property string ramStyle: Style.barWidgetStyle("ram", "text")
}
