import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The Remote Desktop panel: status, power, credentials, network, display and the
// advanced audio/video options, all driven through the helpers bundled next to this
// file. Nothing here talks to hypr-rdp itself — every mutation goes through a
// script, so the panel and the runtime it drives always ship together and the
// same validation applies whether a value was typed here or in a terminal.
Panel {
  id: root
  moduleName: "io.github.yudopr11.omarchy-remote-desktop-server"

  property var anchorItem: null
  property var hostWidget: null

  // Absolute plugin directory. Helper paths are built from this, never from
  // ~/.local/bin, so an update of the plugin takes effect immediately (and the
  // status helper reports the drift instead of the panel hiding it).
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color mutedForeground: Qt.darker(foreground, 1.35)
  readonly property color warnColor: Color.urgent

  // ---------------------------------------------------------------- state

  property var status: null
  property var config: null
  property string statusError: ""
  property string actionError: ""
  property string actionLabel: ""
  property bool restartAfter: false
  property bool syncPending: true
  property bool advancedOpen: false

  // Form fields keep their own state so the 5 s refresh cannot pull the ground
  // out from under something being typed. syncForm() re-seeds them when the
  // panel opens or an action has just finished.
  property string formMode: "localhost"
  property string formAddress: ""
  property string formCustom: ""
  property string formPort: "3389"
  property string formUsername: ""
  property int formFps: 30
  property int formBitrateMbit: 8
  property string formBackend: "auto"
  property string formCapture: "none"
  property string formAudioMode: "default"

  readonly property bool haveStatus: status !== null
  readonly property bool installed: haveStatus && status.installed === true
  readonly property bool configured: haveStatus && status.configured === true
  readonly property bool armed: haveStatus && status.armed === true
  readonly property bool active: haveStatus && status.active === true
  readonly property bool listening: haveStatus && status.listening === true
  readonly property bool storedPassword: haveStatus && status.storedPassword === true
  readonly property bool autostart: haveStatus && status.autostart === true
  readonly property bool runtimeInstalled: haveStatus && status.runtimeInstalled === true
  readonly property bool runtimeStale: haveStatus && status.runtimeStale === true
  readonly property bool busy: actionLabel !== ""

  readonly property string bindHost: haveStatus && status.host ? String(status.host) : "127.0.0.1"
  readonly property int bindPort: haveStatus && status.port ? Number(status.port) : 3389
  readonly property string endpoint: haveStatus && status.endpoint ? String(status.endpoint) : "unknown"
  readonly property bool loopback: bindHost === "127.0.0.1"
  readonly property var monitors: config && config.monitors ? config.monitors : []
  readonly property var addresses: config && config.addresses ? config.addresses : []
  readonly property string output: config && config.output ? String(config.output) : ""
  readonly property string version: haveStatus && status.version ? String(status.version) : ""

  readonly property string chipText: {
    if (!haveStatus) return statusError !== "" ? "Status unavailable" : "Reading status…"
    if (!installed) return "Setup required"
    if (!armed) return "Password required"
    if (active && listening) return "Connected-ready"
    return "Stopped"
  }
  readonly property color chipColor: {
    if (!haveStatus) return statusError !== "" ? warnColor : mutedForeground
    if (!installed || !armed) return warnColor
    if (active && listening) return Color.accent
    return mutedForeground
  }

  // ---------------------------------------------------------------- helpers

  function script(name) {
    return pluginDir + "/scripts/" + name
  }

  function quote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // Interactive work (password, install, logs) happens in a terminal: the panel
  // never sees the plaintext and never has to grow a password field.
  function openInTerminal(command) {
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-lc",
      command + "; code=$?; printf '\\n[exit %s] press Enter to close\\n' \"$code\"; read -r _"])
  }

  function copyToClipboard(value) {
    if (!value || value === "unknown") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  function bindModeFor(host) {
    if (host === "127.0.0.1") return "localhost"
    if (host === "0.0.0.0") return "lan"
    if (addresses.indexOf(host) >= 0) return "address"
    return "custom"
  }

  function syncForm() {
    if (!status || !config) return
    formMode = bindModeFor(bindHost)
    formPort = String(bindPort)
    formAddress = addresses.indexOf(bindHost) >= 0 ? bindHost : (addresses.length > 0 ? String(addresses[0]) : "")
    formCustom = bindModeFor(bindHost) === "custom" ? bindHost : ""
    formUsername = config.username ? String(config.username) : ""
    formFps = config.fps ? Number(config.fps) : 30
    formBitrateMbit = config.bitrate ? Math.max(1, Math.round(Number(config.bitrate) / 1000000)) : 8
    formBackend = config.h264Backend ? String(config.h264Backend) : "auto"
    formCapture = config.captureMode ? String(config.captureMode) : "none"
    formAudioMode = config.audioMode ? String(config.audioMode) : "default"
    syncPending = false
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!configProc.running) configProc.running = true
  }

  function applyStatus(text) {
    try {
      root.status = JSON.parse(text)
      root.statusError = ""
    } catch (e) {
      root.status = null
      root.statusError = "could not read status"
    }
    if (root.syncPending) root.syncForm()
  }

  function applyConfig(text) {
    try {
      root.config = JSON.parse(text)
    } catch (e) {
      root.config = null
    }
    if (root.syncPending) root.syncForm()
  }

  function runAction(args, label) {
    if (actionProc.running || args.length === 0) return
    root.actionError = ""
    root.actionLabel = label
    actionProc.command = args
    actionProc.running = true
  }

  function actionFailed(code, text) {
    if (code === 0) return false
    var message = String(text || "").trim()
    if (message.indexOf("{") === 0) {
      try {
        var data = JSON.parse(message)
        if (data.error) {
          root.actionError = String(data.error)
          return true
        }
        if (data.ready === false) {
          root.actionError = "server did not come up — see Logs"
          return true
        }
      } catch (e) {
        // fall through to the generic message
      }
    }
    root.actionError = message !== "" ? message : ("action failed (exit " + code + ")")
    return true
  }

  function finishAction(code) {
    var out = actionOut.text
    var failed = actionFailed(code, out)
    root.actionLabel = ""
    if (failed) {
      root.restartAfter = false
    } else if (root.restartAfter) {
      // A config change only takes effect when the running server restarts.
      root.restartAfter = false
      root.runAction(["bash", script("omarchy-rdp-config"), "restart"], "Restarting")
      return
    }
    root.syncPending = true
    root.refresh()
  }

  // ---------------------------------------------------------------- actions

  function startServer() {
    if (!installed) {
      installRuntime()
      return
    }
    if (!armed) {
      setPassword()
      return
    }
    runAction(["bash", script("omarchy-rdp-config"), "start"], "Starting")
  }

  function installRuntime() {
    openInTerminal("bash " + quote(pluginDir + "/install.sh"))
  }

  function updateRuntime() {
    openInTerminal("bash " + quote(pluginDir + "/install.sh") + " --skip-password")
  }

  function setPassword() {
    openInTerminal("bash " + quote(script("omarchy-rdp-password")))
  }

  function stopDisarm() {
    runAction(["bash", script("omarchy-rdp-stop")], "Stopping")
  }

  function stopForgetPassword() {
    runAction(["bash", script("omarchy-rdp-stop"), "--forget"], "Forgetting password")
  }

  function saveUsername(value) {
    runAction(["bash", script("omarchy-rdp-config"), "set", "username", "--value", value], "Saving username")
  }

  function applyBind() {
    var args = ["bash", script("omarchy-rdp-config"), "set", "bind", "--mode", formMode]
    if (formMode === "address") args.push("--host", formAddress)
    else if (formMode === "custom") args.push("--host", formCustom)
    args.push("--port", formPort)
    root.restartAfter = true
    runAction(args, "Applying address")
  }

  function applyOutput(value) {
    root.restartAfter = true
    runAction(["bash", script("omarchy-rdp-config"), "set", "output", "--value", value], "Applying display")
  }

  function applyAutostart(next) {
    runAction(["bash", script("omarchy-rdp-config"), "set", "autostart", "--value", next ? "on" : "off"],
              next ? "Arming at login" : "Disarming autostart")
  }

  function applyAdvanced() {
    var args = ["bash", script("omarchy-rdp-config"), "set", "opt",
                "--fps", String(formFps),
                "--bitrate", String(formBitrateMbit * 1000000),
                "--h264-backend", formBackend,
                "--capture-mode", formCapture,
                "--audio-mode", formAudioMode]
    root.restartAfter = true
    runAction(args, "Applying advanced settings")
  }

  function watchLogs() {
    openInTerminal("journalctl --user -u hypr-rdp.service -b --no-pager")
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: statusProc
    command: ["bash", root.script("omarchy-rdp-status")]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.status = null
        root.statusError = String(statusErr.text || "").trim() || "status failed"
        return
      }
      root.applyStatus(statusOut.text)
    }
  }

  Process {
    id: configProc
    command: ["bash", root.script("omarchy-rdp-config"), "get"]
    stdout: StdioCollector { id: configOut; waitForEnd: true }
    stderr: StdioCollector { id: configErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      root.applyConfig(configOut.text)
    }
  }

  Process {
    id: actionProc
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      var message = String(actionErr.text || "").trim()
      if (message !== "") console.warn("remote-desktop", message)
      root.finishAction(code)
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  onOpenedChanged: {
    if (!opened) return
    root.syncPending = true
    root.actionError = ""
    root.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    // Drop the panel under the RDP pill; the framework clamps it to the screen
    // edge, so a right-hand bar section cannot push it off-screen.
    centerOnBar: false
    focusTarget: catcher
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(10)

        // 1 — header ------------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - chip.width - parent.spacing
            text: "Remote Desktop"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Rectangle {
            id: chip
            width: chipLabel.implicitWidth + Style.space(14)
            height: chipLabel.implicitHeight + Style.space(6)
            radius: height / 2
            color: Qt.rgba(root.chipColor.r, root.chipColor.g, root.chipColor.b, 0.16)
            border.width: 1
            border.color: root.chipColor

            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: root.chipText
              color: root.chipColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Text {
          width: parent.width
          visible: !root.haveStatus && root.statusError !== ""
          text: root.statusError
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          visible: root.actionError !== ""
          text: root.actionError
          color: root.warnColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          visible: root.actionLabel !== ""
          text: root.actionLabel + "…"
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          visible: root.runtimeStale
          text: "The installed helpers differ from this plugin's copy — Update runtime to refresh them."
          color: root.warnColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // 2 — package -----------------------------------------------------
        PanelSectionHeader { text: "PACKAGE"; foreground: root.foreground; fontFamily: root.fontFamily }
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - installButton.width - parent.spacing
            text: root.installed
              ? "Installed" + (root.version !== "" ? "  " + root.version : "")
              : (root.haveStatus ? "Missing" : "Unknown")
            color: root.installed ? root.foreground : root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            id: installButton
            visible: !root.installed
            text: "Install"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.installRuntime()
          }

          Button {
            visible: root.installed && root.runtimeStale
            text: "Update runtime"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.updateRuntime()
          }
        }

        PanelSeparator { foreground: root.foreground }

        // 3 — power -------------------------------------------------------
        PanelSectionHeader { text: "POWER"; foreground: root.foreground; fontFamily: root.fontFamily }
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            visible: !root.active
            width: parent.width
            text: root.armed ? "Start" : "Start (set password)"
            bordered: true
            enabled: !root.busy && (root.installed || root.haveStatus)
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.startServer()
          }

          Button {
            visible: root.active
            width: parent.width
            text: "Stop & disarm"
            bordered: true
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.stopDisarm()
          }
        }

        Text {
          width: parent.width
          visible: root.storedPassword
          text: "A stored password keeps this machine reachable after a logout; stopping now only stops it until the next login."
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          visible: root.storedPassword
          text: "Stop & forget password"
          bordered: true
          enabled: !root.busy
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.stopForgetPassword()
        }

        PanelSeparator { foreground: root.foreground }

        // 4 — credentials -------------------------------------------------
        PanelSectionHeader { text: "CREDENTIALS"; foreground: root.foreground; fontFamily: root.fontFamily }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: usernameField
            width: parent.width - saveUsernameButton.width - parent.spacing
            text: root.formUsername
            placeholderText: "Username"
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.formUsername = text
            onAccepted: root.saveUsername(text)
          }

          Button {
            id: saveUsernameButton
            text: "Save"
            bordered: true
            enabled: !root.busy && root.formUsername !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.saveUsername(usernameField.text)
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - setPasswordButton.width - parent.spacing
            text: "Password: " + (root.storedPassword ? "stored on disk"
                                 : root.armed ? "held in RAM" : "not set")
            color: root.armed ? root.foreground : root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            id: setPasswordButton
            text: "Set password"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setPassword()
          }
        }

        PanelSeparator { foreground: root.foreground }

        // 5 — network -----------------------------------------------------
        PanelSectionHeader { text: "NETWORK"; foreground: root.foreground; fontFamily: root.fontFamily }

        Dropdown {
          width: parent.width
          label: "Listen on"
          value: root.formMode
          options: [
            { value: "localhost", label: "This machine only (127.0.0.1)" },
            { value: "lan", label: "Any interface (0.0.0.0)" },
            { value: "address", label: "A specific address" },
            { value: "custom", label: "A hostname or address I type" }
          ]
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.formMode = value }
        }

        Dropdown {
          width: parent.width
          visible: root.formMode === "address"
          label: "Address"
          value: root.formAddress
          options: root.addresses
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.formAddress = value }
        }

        TextField {
          width: parent.width
          visible: root.formMode === "custom"
          text: root.formCustom
          placeholderText: "hostname or address"
          foreground: root.foreground
          font.family: root.fontFamily
          onTextChanged: root.formCustom = text
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: portField
            width: (parent.width - applyBindButton.width - parent.spacing * 2) / 2
            text: root.formPort
            placeholderText: "Port"
            foreground: root.foreground
            font.family: root.fontFamily
            validator: IntValidator { bottom: 1; top: 65535 }
            onTextChanged: root.formPort = text
            onAccepted: root.applyBind()
          }

          Button {
            id: applyBindButton
            text: "Apply"
            bordered: true
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.applyBind()
          }

          Button {
            text: "Copy address"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.copyToClipboard(root.endpoint)
          }
        }

        Text {
          width: parent.width
          text: "Connect to " + root.endpoint
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: !root.loopback
          text: "Visible to the whole network — only accept clients you trust, and prefer a firewall rule that names them."
          color: root.warnColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // 6 — display -----------------------------------------------------
        PanelSectionHeader { text: "DISPLAY"; foreground: root.foreground; fontFamily: root.fontFamily }

        Dropdown {
          id: displayDropdown
          width: parent.width
          label: "Screen"
          value: root.output !== "" ? root.output : "virtual"
          options: {
            var list = [{ value: "virtual", label: "Virtual display (no physical screen)" }]
            for (var i = 0; i < root.monitors.length; i++) {
              var m = root.monitors[i]
              list.push({ value: String(m.name),
                          label: String(m.name) + "  " + m.width + "×" + m.height })
            }
            return list
          }
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.applyOutput(value) }
        }

        PanelSeparator { foreground: root.foreground }

        // 7 — autostart ---------------------------------------------------
        Toggle {
          width: parent.width
          label: "Start at login"
          description: root.storedPassword
            ? "The password is stored on disk, so the server re-arms with your session."
            : "Needs a stored password; enabling this keeps one in ~/.config/hypr-rdp."
          checked: root.autostart
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: if (!root.busy) root.applyAutostart(!root.autostart)
        }

        PanelSeparator { foreground: root.foreground }

        // 8 — advanced ----------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            width: parent.width - advancedToggle.width - parent.spacing
            text: "ADVANCED"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ToggleSwitch {
            id: advancedToggle
            checked: advancedOpen
            foreground: root.foreground
            onToggled: root.advancedOpen = !root.advancedOpen
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: advancedOpen

          PanelSectionHeader { text: "AUDIO"; foreground: root.foreground; fontFamily: root.fontFamily }

          Dropdown {
            width: parent.width
            label: "Audio mode"
            value: root.formAudioMode
            options: [
              { value: "default", label: "Default (hypr-rdp)" },
              { value: "off", label: "Off" },
              { value: "redirect", label: "Redirect" },
              { value: "mirror", label: "Mirror" }
            ]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { root.formAudioMode = value }
          }

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader { text: "VIDEO"; foreground: root.foreground; fontFamily: root.fontFamily }

          NumberField {
            width: parent.width
            label: "Frames per second"
            value: root.formFps
            from: 1
            to: 120
            foreground: root.foreground
            fontFamily: root.fontFamily
            onModified: function(value) { root.formFps = value }
          }

          NumberField {
            width: parent.width
            label: "Bitrate (Mbit/s)"
            value: root.formBitrateMbit
            from: 1
            to: 100
            foreground: root.foreground
            fontFamily: root.fontFamily
            onModified: function(value) { root.formBitrateMbit = value }
          }

          Dropdown {
            width: parent.width
            label: "H.264 backend"
            value: root.formBackend
            options: [
              { value: "auto", label: "Automatic (hardware, else software)" },
              { value: "vaapi", label: "VAAPI" },
              { value: "software", label: "Software" }
            ]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { root.formBackend = value }
          }

          Dropdown {
            width: parent.width
            label: "Capture mode"
            value: root.formCapture
            options: [
              { value: "none", label: "Default (compositor)" },
              { value: "wlr", label: "wlr" },
              { value: "ext", label: "ext" }
            ]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { root.formCapture = value }
          }

          Button {
            width: parent.width
            text: "Apply advanced settings"
            bordered: true
            enabled: !root.busy && root.installed
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.applyAdvanced()
          }
        }

        PanelSeparator { foreground: root.foreground }

        // 9 — footer ------------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Refresh"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.syncPending = true; root.refresh() }
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Logs"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.watchLogs()
          }
        }

        Text {
          width: parent.width
          text: "Changing settings restarts the service, so connected clients reconnect."
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
