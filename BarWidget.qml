import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Bar pill for Remote Desktop.
//
// Owns the button and lazily loads the panel, forwarding the open/close
// contract the bar's popout coordinator expects. Panel.qml gets the host
// objects it needs through inject().
//
// The mark is drawn rather than typed: a thin ring with the two inward
// chevrons of the Remote Desktop logo. A transparent WidgetButton sits on top
// so hover, tooltips and the bar's click registration keep working.
BarWidget {
  id: root
  moduleName: "io.github.yudopr11.omarchy-remote-desktop-server"

  readonly property bool opened: loader.item ? loader.item.opened === true : false
  readonly property real markSize: Math.max(12, Math.round(Style.bar.iconSlot * 0.85))
  readonly property real markStroke: Math.max(1, markSize / 16)
  readonly property color markColor: root.bar ? root.bar.barForeground : Color.foreground
  readonly property real openPanelIndicatorWidth: markSize
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: loader.item ? loader.item.popoutSwitchClosing === true : false

  function open() { if (loader.item) loader.item.open() }
  function close() { if (loader.item) loader.item.close() }
  function togglePanel() { if (loader.item) loader.item.toggle() }
  function closeForPopoutSwitch() { if (loader.item) loader.item.closeForPopoutSwitch() }

  function inject() {
    if (!loader.item) return
    loader.item.bar = root.bar
    loader.item.settings = root.settings
    loader.item.anchorItem = button
    loader.item.hostWidget = root
  }

  implicitWidth: markSize + Style.space(4)
  implicitHeight: button.implicitHeight
  onBarChanged: inject()
  onSettingsChanged: inject()

  Loader {
    id: loader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.inject(); Qt.callLater(root.inject) }
  }

  // Remote Desktop mark: a ring with the "> <" chevron pair inside.
  Item {
    id: mark
    anchors.centerIn: parent
    width: root.markSize
    height: root.markSize

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: width / 2
      border.width: root.markStroke
      border.color: root.markColor
    }

    Shape {
      anchors.fill: parent

      ShapePath {
        strokeColor: root.markColor
        strokeWidth: root.markStroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.MiterJoin

        PathPolyline {
          path: [Qt.point(mark.width * 0.31, mark.height * 0.35),
                 Qt.point(mark.width * 0.47, mark.height * 0.50),
                 Qt.point(mark.width * 0.31, mark.height * 0.65)]
        }
        PathPolyline {
          path: [Qt.point(mark.width * 0.69, mark.height * 0.35),
                 Qt.point(mark.width * 0.53, mark.height * 0.50),
                 Qt.point(mark.width * 0.69, mark.height * 0.65)]
        }
      }
    }
  }

  // Transparent hit area: keeps the tooltip, cursor and click registration that
  // WidgetButton provides without painting a label of its own.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    keepSpace: true
    tooltipText: "Remote Desktop"
    horizontalMargin: 0
    verticalPadding: 0

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
