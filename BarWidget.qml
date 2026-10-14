import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// Bar pill for Remote Desktop.
//
// Owns the button and lazily loads the panel, forwarding the open/close
// contract the bar's popout coordinator expects. Panel.qml gets the host
// objects it needs through inject().
//
// The mark is assets/remote-desktop.svg, tinted to the bar's foreground colour.
// A transparent WidgetButton sits on top so hover, tooltips and the bar's click
// registration keep working.
BarWidget {
  id: root
  moduleName: "io.github.yudopr11.omarchy-remote-desktop-server"

  readonly property bool opened: loader.item ? loader.item.opened === true : false
  readonly property real markSize: Math.max(12, Math.round(Style.bar.iconSlot * 0.62))
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

  // Remote Desktop mark: monitor, stand and the remote-connection badge.
  Item {
    id: mark
    anchors.centerIn: parent
    width: root.markSize
    height: root.markSize

    Image {
      id: markImage
      anchors.fill: parent
      visible: false
      source: Qt.resolvedUrl("assets/remote-desktop.svg")
      sourceSize: Qt.size(Math.round(width * 2), Math.round(height * 2))
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    MultiEffect {
      anchors.fill: markImage
      source: markImage
      colorization: 1.0
      colorizationColor: root.markColor
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
