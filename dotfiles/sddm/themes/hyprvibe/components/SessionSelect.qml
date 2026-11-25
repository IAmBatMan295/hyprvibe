import QtQuick

Item {
    id: root
    width: parent ? parent.width : 200
    height: 44
    z: popup.visible ? 90 : 5

    property var model: sessionModel
    property int selectedIndex: -1

    function getSessionName(idx) {
        if (!model || idx < 0 || idx >= model.rowCount()) return "Hyprland"
        var mi = model.index(idx, 0)
        return String(model.data(mi, 260) || model.data(mi, Qt.DisplayRole) || "Hyprland")
    }

    function getInvertedIndex(visualIdx) {
        if (!model || model.rowCount() === 0) return 0
        return model.rowCount() - 1 - visualIdx
    }

    function resolveDefaultIndex() {
        if (!model || model.rowCount() === 0) return 0
        // Honor SDDM RememberLastSession state when a valid saved index is provided
        if (model.lastIndex !== undefined && model.lastIndex >= 0 && model.lastIndex < model.rowCount())
            return model.lastIndex
        // Otherwise prefer uwsm hyprland session, then any hyprland session
        for (var i = 0; i < model.rowCount(); i++) {
            var sName = getSessionName(i).toLowerCase()
            if (sName.indexOf("uwsm") !== -1 && sName.indexOf("hyprland") !== -1)
                return i
        }
        for (var j = 0; j < model.rowCount(); j++) {
            var name = getSessionName(j).toLowerCase()
            if (name.indexOf("hyprland") !== -1)
                return j
        }
        return 0
    }

    readonly property int currentIndex: (selectedIndex >= 0 && model && selectedIndex < model.rowCount())
        ? selectedIndex
        : resolveDefaultIndex()

    readonly property string currentSessionName: getSessionName(currentIndex)

    function scrollToSelected() {
        if (!model || model.rowCount() === 0) return
        var visualIdx = model.rowCount() - 1 - root.currentIndex
        if (visualIdx >= 0 && visualIdx < sessionList.count) {
            sessionList.positionViewAtIndex(visualIdx, ListView.Contain)
        }
    }

    readonly property bool isOpen: popup.visible
    function toggle() { popup.visible = !popup.visible }
    function open() { popup.visible = true }
    function close() { popup.visible = false }

    property color surfaceColor
    property color textColor
    property color accentColor
    property color mutedColor
    property color borderColor
    property string fontFamily

    // Box with 1px border, no background change on hover, both icon & text hover to accent
    Rectangle {
        id: headerBox
        anchors.fill: parent
        radius: 0
        color: "transparent"
        border.width: 1
        border.color: headerArea.containsMouse || popup.visible ? root.accentColor : root.borderColor

        Row {
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, implicitWidth)
            spacing: 8

            // Icon: hovers to accent
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 15
                color: headerArea.containsMouse ? root.accentColor : root.textColor
            }

            // Session name: hovers to accent, elides if long
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, headerBox.width - 50)
                text: root.currentSessionName
                font.family: root.fontFamily
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
                color: headerArea.containsMouse ? root.accentColor : root.textColor
                renderType: Text.NativeRendering
            }
        }

        MouseArea {
            id: headerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }

    // Dropdown Session List Popup (opens UPWARDS, sequence inverted with selected nearest to box)
    Rectangle {
        id: popup
        visible: false
        onVisibleChanged: {
            if (visible) Qt.callLater(root.scrollToSelected)
        }
        width: parent.width
        height: Math.min(Math.max(1, (root.model ? root.model.rowCount() : 1)) * 38 + 2, 180)
        anchors.bottom: headerBox.top
        anchors.bottomMargin: 4
        anchors.left: headerBox.left
        radius: 0
        color: root.surfaceColor
        border.color: root.accentColor
        border.width: 1
        clip: true

        ListView {
            id: sessionList
            anchors.fill: parent
            anchors.margins: 1
            model: root.model
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: itemRect
                width: sessionList.width
                height: 38
                radius: 0
                color: "transparent"

                readonly property int modelIdx: root.getInvertedIndex(index)
                readonly property color itemStateColor: itemArea.containsMouse ? root.accentColor : (modelIdx === root.currentIndex ? root.textColor : root.mutedColor)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelIdx === root.currentIndex ? "●" : "○"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: itemRect.itemStateColor
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34
                        text: String(root.getSessionName(modelIdx))
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.bold: modelIdx === root.currentIndex
                        elide: Text.ElideRight
                        color: itemRect.itemStateColor
                        renderType: Text.NativeRendering
                    }
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedIndex = modelIdx
                        root.close()
                    }
                }
            }
        }
    }
}
