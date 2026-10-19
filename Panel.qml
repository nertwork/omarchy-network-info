import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "nertwork.network-info"
  ipcTarget: "nertwork.network-info"
  manageIpc: false

  property var localData: ({})
  property var publicData: ({})

  readonly property var displayModes: ["both", "private", "public", "speed", "icon"]
  readonly property var barSpeedModes: ["off", "compact", "stacked", "active", "full"]
  readonly property var chartWindows: [60, 300, 900, 1800]

  property string displayMode: "both"
  property string barSpeedMode: "stacked"
  property bool hideSpeedWhenIdle: false
  property string interfaceScope: "primary"
  property bool showGraph: true
  property bool showPerApp: true
  property int chartWindow: 300
  property int speedInterval: 2000

  readonly property string configFilePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/settings/nertwork.network-info.json"

  // Live speed & throughput state
  property real downRate: 0
  property real upRate: 0
  property real smoothDown: 0
  property real smoothUp: 0
  property real peakDown: 0
  property real peakUp: 0
  property real sessionDown: 0
  property real sessionUp: 0
  property real totalRx: 0
  property real totalTx: 0
  property var prevSample: null
  property real prevSampleAt: 0
  property var history: []
  property var ifaceRates: ({})
  property var appRows: []

  function normalizeMode(m) {
    if (!m) return "both"
    var lower = String(m).toLowerCase().trim()
    if (lower === "primary") return "private"
    return displayModes.indexOf(lower) >= 0 ? lower : "both"
  }

  function normalizeSpeedMode(m) {
    if (!m) return "stacked"
    var lower = String(m).toLowerCase().trim()
    return barSpeedModes.indexOf(lower) >= 0 ? lower : "stacked"
  }

  function saveSettings() {
    try {
      var cfg = {
        displayMode: root.displayMode,
        barSpeedMode: root.barSpeedMode,
        hideSpeedWhenIdle: root.hideSpeedWhenIdle,
        interfaceScope: root.interfaceScope,
        showGraph: root.showGraph,
        showPerApp: root.showPerApp,
        chartWindow: root.chartWindow,
        speedInterval: root.speedInterval
      }
      configFile.setText(JSON.stringify(cfg, null, 2) + "\n")
    } catch (e) {
      console.warn("nertwork.network-info: failed writing settings: " + e)
    }
  }

  function setDisplayMode(mode) {
    var norm = normalizeMode(mode)
    if (root.displayMode === norm) return
    root.displayMode = norm
    saveSettings()
  }

  function cycleDisplayMode() {
    var idx = displayModes.indexOf(root.displayMode)
    root.setDisplayMode(displayModes[(idx + 1) % displayModes.length])
  }

  function setBarSpeedMode(mode) {
    var norm = normalizeSpeedMode(mode)
    if (root.barSpeedMode === norm) return
    root.barSpeedMode = norm
    saveSettings()
  }

  function cycleBarSpeedMode() {
    var idx = barSpeedModes.indexOf(root.barSpeedMode)
    root.setBarSpeedMode(barSpeedModes[(idx + 1) % barSpeedModes.length])
  }

  function applySettingsFromShell() {
    var dm = root.setting("displayMode", null)
    if (dm !== null && dm !== undefined) root.displayMode = normalizeMode(dm)
    var sm = root.setting("barSpeedMode", null)
    if (sm !== null && sm !== undefined) root.barSpeedMode = normalizeSpeedMode(sm)
    var hi = root.setting("hideSpeedWhenIdle", null)
    if (hi !== null && hi !== undefined) root.hideSpeedWhenIdle = Boolean(hi)
    var sc = root.setting("interfaceScope", null)
    if (sc === "primary" || sc === "all") root.interfaceScope = sc
    var sg = root.setting("showGraph", null)
    if (sg !== null && sg !== undefined) root.showGraph = Boolean(sg)
    var sp = root.setting("showPerApp", null)
    if (sp !== null && sp !== undefined) root.showPerApp = Boolean(sp)
    var cw = Number(root.setting("chartWindow", 0))
    if (chartWindows.indexOf(cw) >= 0) root.chartWindow = cw
    var si = Number(root.setting("speedInterval", 0))
    if (si >= 1000 && si <= 10000) root.speedInterval = si
  }

  FileView {
    id: configFile
    path: root.configFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var raw = text().trim()
        if (!raw) return
        var p = JSON.parse(raw)
        if (!p) return
        if (p.displayMode) root.displayMode = root.normalizeMode(p.displayMode)
        if (p.barSpeedMode) root.barSpeedMode = root.normalizeSpeedMode(p.barSpeedMode)
        if (typeof p.hideSpeedWhenIdle === "boolean") root.hideSpeedWhenIdle = p.hideSpeedWhenIdle
        if (p.interfaceScope === "primary" || p.interfaceScope === "all") root.interfaceScope = p.interfaceScope
        if (typeof p.showGraph === "boolean") root.showGraph = p.showGraph
        if (typeof p.showPerApp === "boolean") root.showPerApp = p.showPerApp
        if (root.chartWindows.indexOf(Number(p.chartWindow)) >= 0) root.chartWindow = Number(p.chartWindow)
        if (Number(p.speedInterval) >= 1000 && Number(p.speedInterval) <= 10000) root.speedInterval = Number(p.speedInterval)
      } catch (e) {
        console.warn("nertwork.network-info: error parsing config: " + e)
      }
    }
  }

  onSettingsChanged: applySettingsFromShell()

  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("bin/network-info.py"))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url)
  }

  // Extracted network data
  readonly property bool connected: localData && localData.connected === true
  readonly property var primaryInfo: localData && localData.primary ? localData.primary : ({})
  readonly property string privateIp: primaryInfo.ip || ""
  readonly property string primaryIface: primaryInfo.iface || ""
  readonly property string primaryType: primaryInfo.type || "ethernet"
  readonly property string gatewayIp: primaryInfo.gateway || ""
  readonly property string gatewayPing: primaryInfo.gatewayPingMs || ""
  readonly property string macAddress: primaryInfo.mac || ""
  readonly property string netmask: primaryInfo.netmask || ""
  readonly property string cidrPrefix: primaryInfo.prefix || ""
  readonly property string primaryIpv6: primaryInfo.ipv6 || ""
  readonly property string primaryIpv6Prefix: primaryInfo.ipv6Prefix || ""
  readonly property string linkSpeed: primaryInfo.speed || ""
  readonly property string linkDuplex: primaryInfo.duplex || ""
  readonly property string wifiSsid: primaryInfo.ssid || ""
  readonly property string wifiSignal: primaryInfo.signal || ""

  readonly property var dnsServers: localData && localData.dns ? localData.dns : []
  readonly property var additionalInterfaces: {
    if (!localData || !localData.interfaces) return []
    var ignoreRe = /^(lo|docker\d*|br-|veth|virbr|cni|flannel|cali|cilium|lxc|dummy)/i
    return localData.interfaces.filter(function(i) {
      return !i.isPrimary && i.ip && (i.state === "UP" || !i.state) && !ignoreRe.test(i.iface || "")
    })
  }

  readonly property string publicIp: publicData && publicData.ip ? publicData.ip : ""
  readonly property string publicOrg: publicData && publicData.org ? publicData.org : ""
  readonly property string publicHostname: publicData && publicData.hostname ? publicData.hostname : ""
  readonly property string publicLocation: {
    if (!publicData) return ""
    var parts = []
    if (publicData.city) parts.push(publicData.city)
    if (publicData.region) parts.push(publicData.region)
    if (publicData.country) parts.push(publicData.country)
    return parts.join(", ")
  }

  readonly property bool refreshing: localProc.running || publicProc.running || publicForceProc.running
  readonly property bool speedIdle: root.smoothDown < 1024 && root.smoothUp < 1024
  readonly property string effectiveSpeedMode: root.displayMode === "speed"
    ? (root.barSpeedMode === "off" ? "compact" : root.barSpeedMode)
    : root.barSpeedMode
  readonly property bool showBarSpeedNow: root.effectiveSpeedMode !== "off" && !(root.hideSpeedWhenIdle && root.speedIdle && root.displayMode !== "speed")
  readonly property bool vertical: bar ? bar.vertical : false

  property string copiedValue: ""
  property string copiedLabel: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimColor: Qt.darker(contentForeground, 1.35)
  readonly property color subDimColor: Qt.darker(contentForeground, 1.65)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property real openPanelIndicatorWidth: button.labelVisible ? button.labelWidth : button.implicitWidth

  function copyToClipboard(val, label) {
    if (!val) return
    Quickshell.execDetached(["wl-copy", "--", String(val)])
    root.copiedValue = String(val)
    root.copiedLabel = label || String(val)
    copiedTimer.restart()
  }

  function applyDevSample(sample) {
    if (!sample) return
    var now = Date.now()
    root.totalRx = sample.rx
    root.totalTx = sample.tx

    if (root.prevSample && root.prevSampleAt > 0 && root.prevSample.iface === sample.iface) {
      var dt = Math.max(0.25, (now - root.prevSampleAt) / 1000.0)
      var dRx = Math.max(0, sample.rx - root.prevSample.rx)
      var dTx = Math.max(0, sample.tx - root.prevSample.tx)
      var instDown = dRx / dt
      var instUp = dTx / dt

      root.downRate = instDown
      root.upRate = instUp
      root.smoothDown = root.smoothDown > 0 ? (root.smoothDown * 0.45 + instDown * 0.55) : instDown
      root.smoothUp = root.smoothUp > 0 ? (root.smoothUp * 0.45 + instUp * 0.55) : instUp
      root.peakDown = Math.max(root.peakDown, root.smoothDown)
      root.peakUp = Math.max(root.peakUp, root.smoothUp)
      root.sessionDown += dRx
      root.sessionUp += dTx

      var nextIfRates = {}
      var curIfs = sample.interfaces || {}
      var prevIfs = root.prevSample.interfaces || {}
      for (var k in curIfs) {
        if (prevIfs[k]) {
          nextIfRates[k] = {
            down: Math.max(0, curIfs[k].rx - prevIfs[k].rx) / dt,
            up: Math.max(0, curIfs[k].tx - prevIfs[k].tx) / dt
          }
        }
      }
      root.ifaceRates = nextIfRates

      var tSec = now / 1000.0
      var cutoff = tSec - 1810
      var nextHist = []
      for (var i = 0; i < root.history.length; i++) {
        if (root.history[i].t >= cutoff) nextHist.push(root.history[i])
      }
      nextHist.push({ t: tSec, down: root.smoothDown, up: root.smoothUp })
      root.history = nextHist
    }
    root.prevSample = sample
    root.prevSampleAt = now
  }

  function refreshAll(force) {
    if (!localProc.running) localProc.running = true
    if (!devProc.running) devProc.running = true
    if (root.opened && root.showPerApp && !ssProc.running) ssProc.running = true
    if (force) {
      if (!publicForceProc.running) publicForceProc.running = true
    } else {
      if (!publicProc.running && !publicForceProc.running) publicProc.running = true
    }
  }

  Timer {
    id: copiedTimer
    interval: 1800
    repeat: false
    onTriggered: {
      root.copiedValue = ""
      root.copiedLabel = ""
    }
  }

  Process {
    id: netMonitorProc
    command: ["ip", "monitor", "address", "route"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { netDebounceTimer.restart() }
    }
    onExited: netMonitorRestartTimer.restart()
  }

  Timer {
    id: netMonitorRestartTimer
    interval: 2000
    repeat: false
    onTriggered: netMonitorProc.running = true
  }

  Timer {
    id: netDebounceTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (!localProc.running) localProc.running = true
    }
  }

  Timer {
    id: devTimer
    interval: Math.max(1000, root.speedInterval)
    running: true
    repeat: true
    onTriggered: {
      if (!devProc.running) devProc.running = true
    }
  }

  Timer {
    id: ssTimer
    interval: 2500
    running: root.opened && root.showPerApp
    repeat: true
    onTriggered: {
      if (!ssProc.running) ssProc.running = true
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      if (!localProc.running) localProc.running = true
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: {
      if (!publicProc.running && !publicForceProc.running) publicProc.running = true
    }
  }

  onOpenedChanged: {
    if (opened) {
      if (!localProc.running) localProc.running = true
      if (!devProc.running) devProc.running = true
      if (root.showPerApp && !ssProc.running) ssProc.running = true
      if (!root.publicIp && !publicProc.running && !publicForceProc.running) {
        publicProc.running = true
      }
    }
  }

  Component.onCompleted: {
    var stateDir = (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/settings"
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    applySettingsFromShell()
    refreshAll(false)
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshAll(true) }
    function cycle(): void { root.cycleDisplayMode() }
    function setMode(mode: string): void { root.setDisplayMode(mode) }
    function getMode(): string { return root.displayMode }
    function cycleSpeed(): void { root.cycleBarSpeedMode() }
    function setSpeedMode(mode: string): void { root.setBarSpeedMode(mode) }
    function getSpeedMode(): string { return root.barSpeedMode }
  }

  Process {
    id: localProc
    command: ["python3", root.scriptPath, "--local"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.length > 65536) return
        try {
          var parsed = JSON.parse(text)
          var prevIp = root.privateIp
          var prevGw = root.gatewayIp
          root.localData = parsed
          if (prevIp && parsed && parsed.primary && (parsed.primary.ip !== prevIp || parsed.primary.gateway !== prevGw)) {
            if (!publicForceProc.running) publicForceProc.running = true
          }
        } catch (e) {
          console.warn("nertwork.network-info: error parsing local data: " + e)
        }
      }
    }
  }

  Timer {
    id: localProcWatchdog
    interval: 8000
    running: localProc.running
    repeat: false
    onTriggered: {
      if (localProc.running) {
        console.warn("nertwork.network-info: localProc watchdog timeout, terminating process")
        localProc.running = false
      }
    }
  }

  Process {
    id: publicProc
    command: ["python3", root.scriptPath, "--public-cached"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.length > 65536) return
        try {
          root.publicData = JSON.parse(text)
        } catch (e) {
          console.warn("nertwork.network-info: error parsing public data: " + e)
        }
      }
    }
  }

  Timer {
    id: publicProcWatchdog
    interval: 10000
    running: publicProc.running
    repeat: false
    onTriggered: {
      if (publicProc.running) {
        console.warn("nertwork.network-info: publicProc watchdog timeout, terminating process")
        publicProc.running = false
      }
    }
  }

  Process {
    id: publicForceProc
    command: ["python3", root.scriptPath, "--public"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.length > 65536) return
        try {
          root.publicData = JSON.parse(text)
        } catch (e) {
          console.warn("nertwork.network-info: error parsing force public data: " + e)
        }
      }
    }
  }

  Timer {
    id: publicForceProcWatchdog
    interval: 10000
    running: publicForceProc.running
    repeat: false
    onTriggered: {
      if (publicForceProc.running) {
        console.warn("nertwork.network-info: publicForceProc watchdog timeout, terminating process")
        publicForceProc.running = false
      }
    }
  }

  Process {
    id: devProc
    command: ["cat", "/proc/net/dev"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.length > 65536) return
        var sample = Model.parseDev(text, root.interfaceScope, root.primaryIface)
        root.applyDevSample(sample)
      }
    }
  }

  Timer {
    id: devProcWatchdog
    interval: 4000
    running: devProc.running
    repeat: false
    onTriggered: {
      if (devProc.running) {
        devProc.running = false
      }
    }
  }

  Process {
    id: ssProc
    command: ["ss", "-tinp", "state", "established"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.length > 65536) return
        root.appRows = Model.parseSS(text)
      }
    }
  }

  Timer {
    id: ssProcWatchdog
    interval: 5000
    running: ssProc.running
    repeat: false
    onTriggered: {
      if (ssProc.running) {
        ssProc.running = false
      }
    }
  }

  readonly property string barBaseText: {
    var priv = root.privateIp ? root.privateIp : "--"
    var pub = root.publicIp ? root.publicIp : "..."
    var netIcon = Model.typeIcon(root.connected ? root.primaryType : "disconnected")
    var pubIcon = Model.publicIcon
    switch (root.displayMode) {
      case "private": return netIcon + " " + priv
      case "public": return pubIcon + " " + pub
      case "speed": return netIcon
      case "icon": return netIcon
      case "both":
      default:
        return netIcon + " " + priv + "  " + pubIcon + " " + pub
    }
  }

  readonly property string barInlineSpeedText: {
    if (!root.showBarSpeedNow) return ""
    var dComp = Model.formatSpeedCompact(root.smoothDown).compact
    var uComp = Model.formatSpeedCompact(root.smoothUp).compact
    switch (root.effectiveSpeedMode) {
      case "compact":
        return "\u2193" + dComp + " \u2191" + uComp
      case "active":
        return (root.smoothUp > root.smoothDown * 1.15) ? ("\u2191 " + uComp) : ("\u2193 " + dComp)
      case "full":
        return "\u2193 " + Model.formatSpeedFull(root.smoothDown) + " \u2191 " + Model.formatSpeedFull(root.smoothUp)
      default:
        return ""
    }
  }

  readonly property bool useStackedBarLayout: root.showBarSpeedNow && root.effectiveSpeedMode === "stacked" && !root.vertical

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: (root.displayMode === "icon" && !root.showBarSpeedNow) ? Style.bar.iconFont : Style.font.caption
    labelVisible: !root.useStackedBarLayout
    hasVisualContent: true
    fixedWidth: root.useStackedBarLayout ? Math.ceil(stackedBarRow.implicitWidth + button.scaledHorizontalMargin * 2) : -1
    text: {
      if (root.useStackedBarLayout) return root.barBaseText
      if (root.displayMode === "speed") {
        return Model.typeIcon(root.connected ? root.primaryType : "disconnected") + (root.barInlineSpeedText ? " " + root.barInlineSpeedText : "")
      }
      return root.barBaseText + (root.barInlineSpeedText ? "  " + root.barInlineSpeedText : "")
    }
    tooltipText: {
      var tip = "Network & IP Info (" + root.displayMode.toUpperCase() + " \u00b7 " + root.barSpeedMode.toUpperCase() + ")\n"
      tip += "Private: " + (root.privateIp || "N/A") + (root.primaryIface ? " (" + root.primaryIface + ")" : "") + "\n"
      tip += "Public:  " + (root.publicIp || "Fetching...") + "\n"
      tip += "Speed:   \u2193 " + Model.formatSpeedFull(root.smoothDown) + "   \u2191 " + Model.formatSpeedFull(root.smoothUp) + "\n"
      if (root.gatewayIp) tip += "Gateway: " + root.gatewayIp + (root.gatewayPing ? " (" + Model.formatPing(Number(root.gatewayPing)) + ")" : "") + "\n"
      tip += "Left: Details \u2022 Middle: Refresh \u2022 Right: Cycle Display \u2022 Scroll: Cycle Speed"
      return tip
    }
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
      else if (b === Qt.MiddleButton) root.refreshAll(true)
      else if (b === Qt.RightButton) root.cycleDisplayMode()
    }
    onWheelMoved: function(delta) {
      root.cycleBarSpeedMode()
    }

    Row {
      id: stackedBarRow
      visible: root.useStackedBarLayout
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.barBaseText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2

        Text {
          textFormat: Text.PlainText
          text: "\u2193" + Model.formatSpeedCompact(root.smoothDown).compact
          color: root.smoothDown >= 1024 ? Color.accent : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Math.max(9, Math.round(button.fontSize * 0.68))
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          textFormat: Text.PlainText
          text: "\u2191" + Model.formatSpeedCompact(root.smoothUp).compact
          color: root.smoothUp >= 1024 ? Color.accent : Qt.darker(button.foreground, 1.25)
          font.family: button.fontFamily
          font.pixelSize: Math.max(9, Math.round(button.fontSize * 0.68))
          renderType: Text.NativeRendering
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight, Style.space(740))

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
          root.close(); event.accepted = true
        } else if (event.key === Qt.Key_R) {
          root.refreshAll(true); event.accepted = true
        } else if (event.key === Qt.Key_M) {
          root.cycleDisplayMode(); event.accepted = true
        } else if (event.key === Qt.Key_S) {
          root.cycleBarSpeedMode(); event.accepted = true
        } else if (event.key === Qt.Key_1 && root.privateIp) {
          root.copyToClipboard(root.privateIp, "Private IP"); event.accepted = true
        } else if (event.key === Qt.Key_2 && root.publicIp) {
          root.copyToClipboard(root.publicIp, "Public IP"); event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          bodyFlick.contentY = Math.min(Math.max(0, bodyFlick.contentHeight - bodyFlick.height), bodyFlick.contentY + Style.space(48))
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          bodyFlick.contentY = Math.max(0, bodyFlick.contentY - Style.space(48))
          event.accepted = true
        }
      }

      Flickable {
        id: bodyFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentCol
          width: bodyFlick.width
          spacing: Style.space(10)

          // 1. Hero Header
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, headerLabels.implicitHeight, refreshBtn.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: Model.typeIcon(root.connected ? root.primaryType : "disconnected")
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              color: root.connected ? Color.accent : Color.urgent
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: headerLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: refreshBtn.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: root.connected ? ("Connected (" + (root.primaryIface || "active") + ")") : "Disconnected"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Rectangle {
                  visible: (root.linkSpeed !== "" || root.wifiSsid !== "")
                  height: Style.space(16)
                  width: badgeTxt.implicitWidth + Style.space(10)
                  radius: Style.space(3)
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: badgeTxt
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.wifiSsid ? (root.wifiSsid + (root.wifiSignal ? " " + root.wifiSignal + "%" : "")) : root.linkSpeed
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                text: {
                  if (!root.connected) return "No default route"
                  var gw = root.gatewayIp ? ("GW " + root.gatewayIp) : "Direct route"
                  var ping = root.gatewayPing ? (" \u00b7 " + Model.formatPing(Number(root.gatewayPing))) : ""
                  return gw + ping
                }
                color: root.dimColor
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            PanelActionButton {
              id: refreshBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.refreshIcon
              tooltipText: "Refresh Network & Public IP (r)"
              hoverColor: Color.accent
              onClicked: root.refreshAll(true)
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // 2. Bar Mode & Speed Selectors + Toggles
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [
                  { id: "both", label: "Both" },
                  { id: "private", label: "Private" },
                  { id: "public", label: "Public" },
                  { id: "speed", label: "Speed" },
                  { id: "icon", label: "Icon" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool isSelected: root.displayMode === modelData.id
                  width: (parent.width - Style.space(16)) / 5
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: isSelected
                    ? Color.accent
                    : (dmMouse.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                  border.width: 1
                  border.color: isSelected ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: isSelected
                    color: isSelected ? (bar ? bar.background : Color.background) : root.contentForeground
                  }

                  MouseArea {
                    id: dmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setDisplayMode(modelData.id)
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [
                  { id: "off", label: "Off" },
                  { id: "compact", label: "Compact" },
                  { id: "stacked", label: "Stacked" },
                  { id: "active", label: "Active" },
                  { id: "full", label: "Full" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool isSelected: root.barSpeedMode === modelData.id
                  width: (parent.width - Style.space(16)) / 5
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: isSelected
                    ? Color.accent
                    : (smMouse.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                  border.width: 1
                  border.color: isSelected ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: isSelected
                    color: isSelected ? (bar ? bar.background : Color.background) : root.contentForeground
                  }

                  MouseArea {
                    id: smMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setBarSpeedMode(modelData.id)
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [
                  { id: "idle", label: "Idle Hide", active: root.hideSpeedWhenIdle },
                  { id: "scope", label: root.interfaceScope === "all" ? "All NICs" : "Primary NIC", active: root.interfaceScope === "all" },
                  { id: "graph", label: "Graph", active: root.showGraph },
                  { id: "apps", label: "Top Apps", active: root.showPerApp }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: (parent.width - Style.space(12)) / 4
                  height: Style.space(20)
                  radius: Style.space(4)
                  color: modelData.active
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                    : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                  border.width: 1
                  border.color: modelData.active ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: modelData.active ? Color.accent : root.dimColor
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.id === "idle") root.hideSpeedWhenIdle = !root.hideSpeedWhenIdle
                      else if (modelData.id === "scope") root.interfaceScope = (root.interfaceScope === "primary" ? "all" : "primary")
                      else if (modelData.id === "graph") root.showGraph = !root.showGraph
                      else if (modelData.id === "apps") root.showPerApp = !root.showPerApp
                      root.saveSettings()
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // 3. Live Throughput Card & Mirrored Dual-Series Canvas Graph
          Rectangle {
            width: parent.width
            implicitHeight: speedCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            border.width: 1
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09)

            Column {
              id: speedCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(12)

                Column {
                  width: (parent.width - Style.space(12)) / 2
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: "\u2193 DOWNLOAD"
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatSpeedFull(root.smoothDown)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Sess " + Model.formatBytes(root.sessionDown) + " \u00b7 Peak " + Model.formatSpeedCompact(root.peakDown).compact
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                Column {
                  width: (parent.width - Style.space(12)) / 2
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: "\u2191 UPLOAD"
                    color: root.dimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatSpeedFull(root.smoothUp)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Sess " + Model.formatBytes(root.sessionUp) + " \u00b7 Peak " + Model.formatSpeedCompact(root.peakUp).compact
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
              }

              Column {
                visible: root.showGraph
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(18)

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "THROUGHPUT HISTORY (" + Math.round(root.chartWindow / 60) + "M)"
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Repeater {
                      model: [
                        { sec: 60, label: "1M" },
                        { sec: 300, label: "5M" },
                        { sec: 900, label: "15M" },
                        { sec: 1800, label: "30M" }
                      ]
                      delegate: Rectangle {
                        required property var modelData
                        readonly property bool activeWin: root.chartWindow === modelData.sec
                        width: Style.space(28)
                        height: Style.space(16)
                        radius: Style.space(3)
                        color: activeWin ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                        Text {
                          textFormat: Text.PlainText
                          anchors.centerIn: parent
                          text: modelData.label
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: activeWin
                          color: activeWin ? (bar ? bar.background : Color.background) : root.dimColor
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            root.chartWindow = modelData.sec
                            root.saveSettings()
                          }
                        }
                      }
                    }
                  }
                }

                Canvas {
                  id: flowCanvas
                  width: parent.width
                  height: Style.space(84)
                  property real hoverX: -1
                  onHoverXChanged: requestPaint()

                  readonly property var pts: {
                    var cut = Date.now() / 1000.0 - root.chartWindow
                    var out = []
                    for (var i = 0; i < root.history.length; i++) {
                      var p = root.history[i]
                      if (p && p.t >= cut) out.push(p)
                    }
                    return out
                  }
                  onPtsChanged: requestPaint()
                  onWidthChanged: requestPaint()

                  HoverHandler {
                    onPointChanged: flowCanvas.hoverX = hovered ? point.position.x : -1
                    onHoveredChanged: if (!hovered) flowCanvas.hoverX = -1
                  }

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    var mid = Math.round(height / 2)
                    ctx.strokeStyle = Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.2)
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(0, mid + 0.5)
                    ctx.lineTo(width, mid + 0.5)
                    ctx.stroke()

                    var p = flowCanvas.pts
                    if (!p || p.length < 2) {
                      ctx.font = "10px " + root.contentFontFamily
                      ctx.fillStyle = root.subDimColor
                      ctx.textAlign = "center"
                      ctx.fillText("Collecting throughput samples...", width / 2, mid - 4)
                      return
                    }

                    var peak = 10 * 1024
                    for (var i = 0; i < p.length; i++) {
                      peak = Math.max(peak, p[i].down || 0, p[i].up || 0)
                    }
                    peak *= 1.1
                    var tNow = Date.now() / 1000.0
                    var tStart = tNow - root.chartWindow
                    var span = Math.max(1, root.chartWindow)
                    var half = mid - 3

                    function xOf(t) {
                      return Math.max(0, Math.min(width - 1, (t - tStart) * (width - 1) / span))
                    }

                    function drawSeries(key, isDown, tint) {
                      ctx.beginPath()
                      ctx.moveTo(xOf(p[0].t), mid)
                      for (var j = 0; j < p.length; j++) {
                        var y = mid + (isDown ? -1 : 1) * half * Math.min(1, (p[j][key] || 0) / peak)
                        ctx.lineTo(xOf(p[j].t), y)
                      }
                      ctx.lineTo(xOf(p[p.length - 1].t), mid)
                      ctx.closePath()
                      ctx.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.24)
                      ctx.fill()

                      ctx.beginPath()
                      for (var k = 0; k < p.length; k++) {
                        var y2 = mid + (isDown ? -1 : 1) * half * Math.min(1, (p[k][key] || 0) / peak)
                        if (k === 0) ctx.moveTo(xOf(p[k].t), y2)
                        else ctx.lineTo(xOf(p[k].t), y2)
                      }
                      ctx.strokeStyle = tint
                      ctx.lineWidth = 1.5
                      ctx.stroke()
                    }

                    drawSeries("down", true, Color.accent)
                    drawSeries("up", false, root.dimColor)

                    if (flowCanvas.hoverX >= 0) {
                      var tAt = tStart + flowCanvas.hoverX * span / Math.max(1, width - 1)
                      var best = p[0], bestD = Math.abs(p[0].t - tAt)
                      for (var h = 1; h < p.length; h++) {
                        var d = Math.abs(p[h].t - tAt)
                        if (d < bestD) { bestD = d; best = p[h] }
                      }
                      var cx = xOf(best.t)
                      ctx.strokeStyle = Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.45)
                      ctx.beginPath()
                      ctx.moveTo(cx + 0.5, 0)
                      ctx.lineTo(cx + 0.5, height)
                      ctx.stroke()

                      ctx.font = "10px " + root.contentFontFamily
                      ctx.fillStyle = root.contentForeground
                      ctx.textAlign = "left"
                      ctx.fillText("\u2193 " + Model.formatSpeedFull(best.down) + "  \u2191 " + Model.formatSpeedFull(best.up), 4, 11)
                    }
                  }
                }
              }
            }
          }

          // 4. Primary Private & Public IP Cards
          Rectangle {
            width: parent.width
            implicitHeight: privTextCol.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: privMouse.containsMouse
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
            border.width: 1
            border.color: privMouse.containsMouse ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

            MouseArea {
              id: privMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyToClipboard(root.privateIp, "Private IP")
            }

            Item {
              id: privRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(10)

              Text {
                id: privIcon
                textFormat: Text.PlainText
                text: Model.typeIcon(root.primaryType)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                color: Color.accent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                id: privTextCol
                anchors.left: privIcon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: privCopyBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: "PRIVATE IP \u00b7 " + (root.privateIp ? (root.privateIp + (root.cidrPrefix ? "/" + root.cidrPrefix : "")) : "Not assigned")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Row {
                  visible: root.netmask !== "" || root.macAddress !== ""
                  spacing: Style.space(6)

                  Text {
                    visible: root.netmask !== ""
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mask " + root.netmask + (root.macAddress !== "" ? " \u00b7" : "")
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    visible: root.macAddress !== ""
                    width: macRow.implicitWidth
                    height: macRow.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                      id: macRow
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "MAC " + root.macAddress
                        color: macMouse.containsMouse ? root.contentForeground : root.subDimColor
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.copiedValue !== "" && (root.copiedValue === root.macAddress || root.copiedLabel === "MAC")) ? Model.checkIcon : Model.copyIcon
                        color: (root.copiedValue !== "" && (root.copiedValue === root.macAddress || root.copiedLabel === "MAC")) ? Color.accent : (macMouse.containsMouse ? Color.accent : root.dimColor)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: macMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.copyToClipboard(root.macAddress, "MAC")
                    }
                  }
                }

                Item {
                  visible: root.primaryIpv6 !== ""
                  width: ipv6Row.implicitWidth
                  height: ipv6Row.implicitHeight

                  Row {
                    id: ipv6Row
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "IPv6 " + root.primaryIpv6 + (root.primaryIpv6Prefix ? "/" + root.primaryIpv6Prefix : "")
                      color: ipv6Mouse.containsMouse ? root.contentForeground : root.subDimColor
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: (root.copiedValue !== "" && (root.copiedValue === root.primaryIpv6 || root.copiedLabel === "IPv6")) ? Model.checkIcon : Model.copyIcon
                      color: (root.copiedValue !== "" && (root.copiedValue === root.primaryIpv6 || root.copiedLabel === "IPv6")) ? Color.accent : (ipv6Mouse.containsMouse ? Color.accent : root.dimColor)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: ipv6Mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyToClipboard(root.primaryIpv6, "IPv6")
                  }
                }
              }

              PanelActionButton {
                id: privCopyBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: (root.copiedValue !== "" && (root.copiedValue === root.privateIp || root.copiedLabel === "Private IP")) ? Model.checkIcon : Model.copyIcon
                foreground: (root.copiedValue !== "" && (root.copiedValue === root.privateIp || root.copiedLabel === "Private IP")) ? Color.accent : root.contentForeground
                tooltipText: "Copy Private IP (1)"
                hoverColor: Color.accent
                onClicked: root.copyToClipboard(root.privateIp, "Private IP")
              }
            }
          }

          Rectangle {
            width: parent.width
            implicitHeight: pubTextCol.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: pubMouse.containsMouse
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
            border.width: 1
            border.color: pubMouse.containsMouse ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

            MouseArea {
              id: pubMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyToClipboard(root.publicIp, "Public IP")
            }

            Item {
              id: pubRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(10)

              Text {
                id: pubIconTxt
                textFormat: Text.PlainText
                text: Model.publicIcon
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                color: Color.accent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                id: pubTextCol
                anchors.left: pubIconTxt.right
                anchors.leftMargin: Style.space(10)
                anchors.right: pubCopyBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: "PUBLIC IP \u00b7 " + (root.publicIp || (root.refreshing ? "Fetching..." : "Offline"))
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  visible: (root.publicOrg !== "" || root.publicLocation !== "")
                  text: [root.publicOrg, root.publicLocation].filter(Boolean).join(" \u00b7 ")
                  color: root.dimColor
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.publicHostname !== ""
                  text: "PTR: " + root.publicHostname
                  color: root.subDimColor
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                  width: parent.width
                }
              }

              PanelActionButton {
                id: pubCopyBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: (root.copiedValue !== "" && (root.copiedValue === root.publicIp || root.copiedLabel === "Public IP")) ? Model.checkIcon : Model.copyIcon
                foreground: (root.copiedValue !== "" && (root.copiedValue === root.publicIp || root.copiedLabel === "Public IP")) ? Color.accent : root.contentForeground
                tooltipText: "Copy Public IP (2)"
                hoverColor: Color.accent
                onClicked: root.copyToClipboard(root.publicIp, "Public IP")
              }
            }
          }

          // 5. Gateway & DNS Card
          Rectangle {
            width: parent.width
            implicitHeight: gwDnsCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            border.width: 1
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

            Column {
              id: gwDnsCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.gatewayIcon + " Gateway:"
                  color: root.dimColor
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Item {
                  width: gwValRow.implicitWidth
                  height: gwValRow.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Row {
                    id: gwValRow
                    spacing: Style.space(5)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: (root.gatewayIp || "N/A") + (root.gatewayPing ? (" (" + Model.formatPing(Number(root.gatewayPing)) + ")") : "")
                      color: gwMouse.containsMouse ? Color.accent : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      visible: root.gatewayIp !== ""
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: (root.copiedValue !== "" && (root.copiedValue === root.gatewayIp || root.copiedLabel === "Gateway")) ? Model.checkIcon : Model.copyIcon
                      color: (root.copiedValue !== "" && (root.copiedValue === root.gatewayIp || root.copiedLabel === "Gateway")) ? Color.accent : (gwMouse.containsMouse ? Color.accent : root.dimColor)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: gwMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.gatewayIp !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (root.gatewayIp) root.copyToClipboard(root.gatewayIp, "Gateway")
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  height: Style.space(18)
                  verticalAlignment: Text.AlignVCenter
                  text: Model.dnsIcon + " DNS:"
                  color: root.dimColor
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: root.dnsServers
                  delegate: Rectangle {
                    required property string modelData
                    readonly property bool isDnsCopied: root.copiedValue !== "" && (root.copiedValue === modelData || root.copiedLabel === ("DNS " + modelData))
                    height: Style.space(18)
                    width: dnsPillRow.implicitWidth + Style.space(10)
                    radius: Style.space(3)
                    color: dnsMouse.containsMouse
                      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                    Row {
                      id: dnsPillRow
                      anchors.centerIn: parent
                      spacing: Style.space(4)

                      Text {
                        id: dnsItemTxt
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: isDnsCopied ? Model.checkIcon : Model.copyIcon
                        color: isDnsCopied ? Color.accent : (dnsMouse.containsMouse ? Color.accent : root.dimColor)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: dnsMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.copyToClipboard(modelData, "DNS " + modelData)
                    }
                  }
                }
              }
            }
          }

          // 6. Additional Interfaces (with per-interface live speed)
          Column {
            visible: root.additionalInterfaces.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "ADDITIONAL INTERFACES"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Repeater {
              model: root.additionalInterfaces
              delegate: Rectangle {
                required property var modelData
                readonly property var ifRate: root.ifaceRates && root.ifaceRates[modelData.iface] ? root.ifaceRates[modelData.iface] : ({ down: 0, up: 0 })
                readonly property bool isIfCopied: root.copiedValue !== "" && (root.copiedValue === modelData.ip || root.copiedLabel === (modelData.iface + " IP"))
                width: contentCol.width
                height: Style.space(26)
                radius: Style.space(4)
                color: addIfMouse.containsMouse
                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
                  : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)

                  Text {
                    id: addIfName
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.typeIcon(modelData.type) + " " + modelData.iface
                    color: root.dimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    width: Style.space(96)
                    elide: Text.ElideRight
                  }

                  Row {
                    anchors.left: addIfName.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: addIfSpeed.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(5)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.ip + (modelData.prefix ? "/" + modelData.prefix : "")
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: isIfCopied ? Model.checkIcon : Model.copyIcon
                      color: isIfCopied ? Color.accent : (addIfMouse.containsMouse ? Color.accent : root.dimColor)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    id: addIfSpeed
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2193" + Model.formatSpeedCompact(ifRate.down).compact + " \u2191" + Model.formatSpeedCompact(ifRate.up).compact
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: addIfMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.copyToClipboard(modelData.ip, modelData.iface + " IP")
                }
              }
            }
          }

          // 7. Top Active Apps
          Column {
            visible: root.showPerApp && root.appRows.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "ACTIVE TCP APPS"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Repeater {
              model: root.appRows
              delegate: Rectangle {
                required property var modelData
                width: contentCol.width
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)

                  Text {
                    id: appNameTxt
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.appIcon + " " + modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    width: Style.space(120)
                    elide: Text.ElideRight
                  }

                  Text {
                    id: appConnsTxt
                    textFormat: Text.PlainText
                    anchors.left: appNameTxt.right
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.conns + (modelData.conns === 1 ? " conn" : " conns")
                    color: root.dimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    width: Style.space(65)
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: appConnsTxt.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.peers && modelData.peers.length > 0 ? modelData.peers.join(", ") : ""
                    color: root.subDimColor
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // 8. Copied Banner & Footer Hint
          Rectangle {
            visible: root.copiedValue !== ""
            width: parent.width
            height: Style.space(24)
            radius: Style.space(4)
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: Model.checkIcon + " Copied " + root.copiedLabel + ": " + root.copiedValue
              color: Color.accent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Click IP to copy \u00b7 m: mode \u00b7 s: speed \u00b7 r: refresh \u00b7 Esc: close"
            color: root.subDimColor
            font.family: root.contentFontFamily
            font.pixelSize: Math.max(9, Style.font.caption - 1)
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
