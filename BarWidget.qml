import QtQuick
import qs.Commons
import qs.Ui

// Bar pill for Remote Desktop.
//
// Owns the button and lazily loads the panel, forwarding the open/close
// contract the bar's popout coordinator expects. Panel.qml gets the host
// objects it needs through inject().
BarWidget {
  id: root
  moduleName: "io.github.yudopr11.omarchy-remote-desktop-server"

  readonly property bool opened: loader.item ? loader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
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

  implicitWidth: button.implicitWidth
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "RDP"
    tooltipText: "Remote Desktop"
    fontSize: Style.font.body
    horizontalMargin: 5
    verticalPadding: 5

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
