import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.separator"

  readonly property int spaceWidth: settings && settings.size !== undefined ? Number(settings.size) : 14

  implicitWidth: vertical ? barSize : spaceWidth
  implicitHeight: vertical ? spaceWidth : barSize
}
