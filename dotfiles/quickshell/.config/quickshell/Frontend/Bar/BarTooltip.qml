import QtQuick
import Quickshell
import qs.Backend.Config
import qs.Frontend.Styles
import qs.Frontend.Ui

// Positioned popup tooltip window anchored to a hovered bar widget.
PopupWindow {
  id: tooltipWindow

  required property QtObject bar
  required property PanelWindow barWindow

  visible: bar.tooltipShown
    && bar.tooltipTarget !== null
    && bar.tooltipText !== ""
    && bar.targetBelongsToWindow(bar.tooltipTarget, barWindow)
  color: "transparent"
  implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
  implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

  anchor {
    id: tooltipAnchor
    window: barWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1
    onAnchoring: {
      var target = bar.tooltipTarget
      if (!bar.targetBelongsToWindow(target, barWindow)) return
      var popupWidth = tooltipWindow.implicitWidth
      var popupHeight = tooltipWindow.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = barWindow.height + 10
      if (bar.position === "bottom") localY = -popupHeight - 10
      else if (bar.position === "left") { localX = barWindow.width + 10; localY = target.height / 2 - popupHeight / 2 }
      else if (bar.position === "right") { localX = -popupWidth - 10; localY = target.height / 2 - popupHeight / 2 }
      var point = barWindow.contentItem.mapFromItem(target, localX, 0)
      tooltipAnchor.rect.x = Math.round(Math.max(10, Math.min(point.x, barWindow.width - popupWidth - 10)))
      tooltipAnchor.rect.y = Math.round(localY)
    }
  }

  BorderSurface {
    id: tooltipBubble
    implicitWidth: tooltipLabel.implicitWidth + 20
    implicitHeight: tooltipLabel.implicitHeight + 14
    color: ThemeStore.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", ThemeStore.tooltip.border, 1)
    radius: Style.cornerRadius

    Text {
      id: tooltipLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: bar.tooltipText
      color: ThemeStore.tooltip.text
      font.family: bar.fontFamily
      font.pixelSize: BarStyle.fontSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
