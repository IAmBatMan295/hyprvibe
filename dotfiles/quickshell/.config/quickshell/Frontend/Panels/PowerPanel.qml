import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

// Launcher-styled Battery widget & sharp telemetry popup bound to PowerService & PanelStyle.
PanelShell {
  id: root
  moduleName: "hyprvibe.power"

  readonly property real barEdgeInset: button.barEdgeInset

  visible: PowerService.batteryPresent
  implicitWidth: PowerService.batteryPresent ? button.implicitWidth : 0
  implicitHeight: PowerService.batteryPresent ? button.implicitHeight : 0

  onOpenedChanged: {
    if (opened) {
      if (!PowerService.batteryPresent) { close(); return }
      PowerService.acquireConsumer()
    } else {
      PowerService.releaseConsumer()
    }
  }

  Connections {
    target: PowerService
    function onBatteryPresentChanged() {
      if (!PowerService.batteryPresent) root.close()
    }
  }

  Component {
    id: batteryGlyphComponent

    OpticalGlyph {
      width: Math.ceil(tightWidth)
      height: BarStyle.iconCanvas
      text: PowerService.batteryIcon()
      displayText: (root.bar && root.bar.dataEffect && root.bar.dataEffect.active)
        ? root.bar.dataEffect.scrambleGlyph(text)
        : text
      fontFamily: button.fontFamily
      fontSize: BarStyle.iconFont
      color: button.effectiveColor
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Math.round(PowerService.batteryFraction * 100) + "%"
    fontSize: BarStyle.fontSize
    horizontalMargin: 6
    verticalPadding: 2
    fixedHeight: root.bar ? root.bar.barSize : BarStyle.sizeHorizontal
    trailingSpacing: Style.space(4)
    trailingComponent: batteryGlyphComponent
    tooltipText: {
      var dev = UPower.displayDevice
      var pct = Math.round(PowerService.batteryFraction * 100) + "%"
      var state = PowerService.modeLabel()
      var rate = (dev && dev.energyRate > 0) ? (" (" + dev.energyRate.toFixed(1) + "W)") : ""
      return state ? (state + ": " + pct + rate) : ("Battery: " + pct)
    }
    onPressed: function(b) {
      if (b !== Qt.LeftButton || !PowerService.batteryPresent) return
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && PowerService.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelHeaderBar {
          id: headerBar
          iconText: PowerService.batteryIcon()
          titleText: "Battery"
        }

        // Inset Energy Card with 0px sharp charge bar
        Rectangle {
          width: parent.width
          implicitHeight: energyCol.implicitHeight + Style.space(16)
          radius: PanelStyle.cornerRadius
          color: PanelStyle.darkBackground
          border.width: 1
          border.color: PanelStyle.subtleBorder

          Column {
            id: energyCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            RowLayout {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: GlitchBus.panelText(PowerService.batteryInfo.percentage || "—")
                color: PanelStyle.lightForeground
                font.family: PanelStyle.fontFamily
                font.pixelSize: PanelStyle.headingSize
                font.bold: true
              }

              Item { Layout.fillWidth: true }

              Text {
                textFormat: Text.PlainText
                text: GlitchBus.panelText(
                  PowerService.chargeThresholdActive
                    ? "Limit Active"
                    : (PowerService.batteryFull ? "Full" : (PowerService.batteryInfo.rate || ""))
                )
                color: PanelStyle.mutedText
                font.family: PanelStyle.fontFamily
                font.pixelSize: PanelStyle.smallSize
                font.bold: true
              }
            }

            Item {
              width: parent.width
              implicitHeight: Style.space(8)

              Rectangle {
                id: barTrack
                anchors.fill: parent
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: PanelStyle.trackFill
              }

              Rectangle {
                anchors.left: barTrack.left
                anchors.verticalCenter: barTrack.verticalCenter
                height: barTrack.height
                radius: Style.cornerRadius > 0 ? barTrack.radius : 0
                color: PowerService.charging ? PanelStyle.accent : PanelStyle.lightForeground
                width: Math.max(barTrack.height, barTrack.width * PowerService.batteryFraction)

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 220 } }
              }
            }
          }
        }

        // Sharp 2x2 Metric Grid
        GridLayout {
          visible: PowerService.batteryInfo.percentage !== undefined
          width: parent.width
          columns: 2
          rowSpacing: Style.space(6)
          columnSpacing: Style.space(6)

          MetricCard {
            Layout.fillWidth: true
            label: "Capacity"
            value: PowerService.batteryInfo.size || "—"
          }
          MetricCard {
            Layout.fillWidth: true
            label: PowerService.chargeThresholdActive ? "Charge Limit" : (PowerService.discharging ? "Time Left" : "Time to Full")
            value: PowerService.chargeThresholdActive
              ? (PowerService.batteryInfo.threshold || "-")
              : (PowerService.batteryFlowIdle ? "-" : (PowerService.batteryInfo.time || "—"))
          }
          MetricCard {
            Layout.fillWidth: true
            label: "Charge Cycles"
            value: PowerService.batteryInfo.cycles || "—"
          }
          MetricCard {
            Layout.fillWidth: true
            label: PowerService.chargeThresholdActive ? "Mode" : (PowerService.discharging ? "Discharge" : "Charge Rate")
            value: PowerService.chargeThresholdActive
              ? "Holding"
              : (PowerService.batteryFull ? "-" : (PowerService.batteryInfo.rate || "—"))
          }
        }
      }
    }
  }

  component MetricCard: Rectangle {
    property string label: ""
    property string value: ""

    implicitHeight: mcCol.implicitHeight + Style.space(12)
    radius: PanelStyle.cornerRadius
    color: PanelStyle.darkBackground
    border.width: 1
    border.color: PanelStyle.subtleBorder

    Column {
      id: mcCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelText(label.toUpperCase())
        color: PanelStyle.mutedText
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.captionSize
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelText(value)
        color: PanelStyle.lightForeground
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.bodySize
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
