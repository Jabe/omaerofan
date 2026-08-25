import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jabe.omaerofan"
  ipcTarget: "jabe.omaerofan"

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return url.replace(/\/$/, "")
  }
  readonly property string cli: pluginDir + "/omaerofan"

  property var status: ({})
  property string lastError: ""
  property var queuedArgs: null
  property int previewCpu: -1
  property int previewGpu: -1
  property int previewBatt: -1
  property string focusSection: "mode"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property bool installed: status.installed === true && status.ok !== false
  readonly property string mode: String(status.mode || "auto")
  readonly property int cpuTemp: Model.num(status.cpu_temp, 0)
  readonly property int gpuTemp: Model.num(status.gpu_temp, 0)
  readonly property int mlbTemp: Model.num(status.mlb_temp, 0)
  readonly property int fan0Rpm: Model.num(status.fan0_rpm, 0)
  readonly property int fan1Rpm: Model.num(status.fan1_rpm, 0)
  readonly property int cpuFan: previewCpu >= 0 ? previewCpu : Model.clampFan(status.fan0_pct)
  readonly property int gpuFan: previewGpu >= 0 ? previewGpu : Model.clampFan(status.fan1_pct)
  readonly property bool batteryOn: status.battery_on === true || status.battery_on === 1
  readonly property int batteryLimit: previewBatt >= 0 ? previewBatt : Model.clampBatt(status.battery_limit)
  readonly property bool dragging: previewCpu >= 0 || previewGpu >= 0 || previewBatt >= 0
    || fanDebounce.running || battDebounce.running
  readonly property bool hot: Model.hottestTemp(status) >= 85
  readonly property var modeOptions: [
    { id: "auto", label: "Auto" },
    { id: "quiet", label: "Quiet" },
    { id: "gaming", label: "Gaming" },
    { id: "manual", label: "Manual" }
  ]
  readonly property var visibleSections: {
    if (!installed) return ["install"]
    return ["mode", "cpu", "gpu", "battery"]
  }
  readonly property color dim: Qt.darker(barForeground, 1.4)
  readonly property string barLabel: Model.barLabel(status)
  readonly property string heroStatusText: {
    if (!installed) return "HELPER MISSING"
    if (lastError) return "ERROR"
    return Model.modeStatus(mode)
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    status = parsed
    if (parsed.ok === false) lastError = String(parsed.error || "status failed")
    else lastError = ""
    if (!root.dragging) {
      previewCpu = -1
      previewGpu = -1
      previewBatt = -1
    }
  }

  function refresh() {
    if (statusProc.running || dragging) return
    statusProc.command = [root.cli, "json"]
    statusProc.running = true
  }

  function runCli(args) {
    queuedArgs = args
    if (actionProc.running) return
    flushCli()
  }

  function flushCli() {
    if (!queuedArgs || actionProc.running) return
    actionProc.command = [root.cli].concat(queuedArgs)
    queuedArgs = null
    actionProc.running = true
  }

  function setMode(next) {
    if (!next || next === mode) return
    runCli([next])
  }

  function commitFans() {
    fanDebounce.stop()
    runCli(["fans", String(Model.clampFan(cpuFan)), String(Model.clampFan(gpuFan))])
  }

  function previewFan(which, value) {
    var pct = Model.clampFan(value)
    if (which === "cpu") previewCpu = pct
    else previewGpu = pct
    fanDebounce.restart()
  }

  function nudgeFan(which, delta) {
    var current = which === "cpu" ? cpuFan : gpuFan
    previewFan(which, current + delta)
  }

  function setBattery(on, pct) {
    if (!on) {
      previewBatt = -1
      runCli(["battery", "off"])
      return
    }
    runCli(["battery", String(Model.clampBatt(pct))])
  }

  function toggleBattery() {
    if (batteryOn) setBattery(false, batteryLimit)
    else setBattery(true, batteryLimit)
  }

  function previewBattery(value) {
    previewBatt = Model.clampBatt(value)
    battDebounce.restart()
  }

  function commitBattery() {
    battDebounce.stop()
    setBattery(true, batteryLimit)
  }

  function installHelper() {
    if (installProc.running) return
    lastError = ""
    installProc.command = [root.cli, "install"]
    installProc.running = true
  }

  function tempColor(temp) {
    var tone = Model.tempTone(temp)
    if (tone === "hot") return bar && bar.urgent ? bar.urgent : Color.urgent
    if (tone === "warm") return Color.accent
    return barForeground
  }

  function sectionFirstIndex(section) {
    if (section === "mode") return 0
    return -1
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections.length) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (focusSection === "mode") {
      var next = selectedIndex + delta
      if (next >= 0 && next < modeOptions.length) { selectedIndex = next; return }
    }
    if (delta > 0 && sIdx < sections.length - 1) {
      focusSection = sections[sIdx + 1]
      selectedIndex = sectionFirstIndex(focusSection)
    } else if (delta < 0 && sIdx > 0) {
      focusSection = sections[sIdx - 1]
      selectedIndex = focusSection === "mode" ? modeOptions.length - 1 : sectionFirstIndex(focusSection)
    }
  }

  function moveCursorH(delta) {
    if (focusSection === "mode") {
      var next = Math.max(0, Math.min(modeOptions.length - 1, selectedIndex + delta))
      selectedIndex = next
      return
    }
    if (focusSection === "cpu") nudgeFan("cpu", delta * 5)
    else if (focusSection === "gpu") nudgeFan("gpu", delta * 5)
    else if (focusSection === "battery") {
      if (!batteryOn) setBattery(true, batteryLimit)
      else previewBattery(batteryLimit + delta * 5)
    }
  }

  function activateCursor() {
    if (focusSection === "install") installHelper()
    else if (focusSection === "mode") setMode(modeOptions[selectedIndex].id)
    else if (focusSection === "battery") toggleBattery()
  }

  function handleTextKey(text) {
    if (text === "1") setMode("auto")
    else if (text === "2") setMode("quiet")
    else if (text === "3") setMode("gaming")
    else if (text === "4") setMode("manual")
    else if (text === "b" || text === "B") toggleBattery()
    else if (text === "r" || text === "R") refresh()
    else if (text === "i" || text === "I") installHelper()
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      focusSection = installed ? "mode" : "install"
      selectedIndex = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.lastError = String(actionErr.text || "command failed").trim()
      if (root.queuedArgs) root.flushCli()
      else root.refresh()
    }
  }

  Process {
    id: installProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: installErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.lastError = String(installErr.text || "install failed").trim()
      root.refresh()
    }
  }

  Timer {
    interval: root.opened ? 1500 : 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: fanDebounce
    interval: 180
    repeat: false
    onTriggered: root.commitFans()
  }

  Timer {
    id: battDebounce
    interval: 180
    repeat: false
    onTriggered: root.commitBattery()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    slotSize: Style.bar.statusSlot
    active: root.hot
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { root.handleTextKey(text) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: Model.fanIcon(root.mode)
              color: root.tempColor(Model.hottestTemp(root.status))
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Omaerofan"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.heroStatusText
                color: root.dim
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          Column {
            visible: !root.installed
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "The EC helper needs a one-time privileged install (gcc + pkexec). It only allows known fan and charge registers."
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            CursorSurface {
              width: parent.width
              implicitHeight: installButton.implicitHeight
              hasCursor: root.cursorActive && root.focusSection === "install"
              foreground: root.bar.foreground
              outline: true

              Button {
                id: installButton
                anchors.left: parent.left
                anchors.right: parent.right
                text: installProc.running ? "Installing…" : "Install helper"
                bordered: true
                enabled: !installProc.running
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.installHelper()
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "install"
                    root.selectedIndex = -1
                  }
                }
              }
            }
          }

          Row {
            visible: root.installed
            width: parent.width
            spacing: Style.space(12)

            TempCell { label: "CPU"; temp: root.cpuTemp; width: (parent.width - parent.spacing * 2) / 3 }
            TempCell { label: "GPU"; temp: root.gpuTemp; width: (parent.width - parent.spacing * 2) / 3 }
            TempCell { label: "MLB"; temp: root.mlbTemp; width: (parent.width - parent.spacing * 2) / 3 }
          }

          PanelSeparator {
            visible: root.installed
            foreground: root.bar.foreground
          }

          Column {
            visible: root.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              id: modeRow
              width: parent.width
              spacing: Style.space(6)
              readonly property real cellWidth: (width - spacing * 3) / 4

              Repeater {
                model: root.modeOptions
                Button {
                  required property var modelData
                  required property int index
                  width: modeRow.cellWidth
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                  bordered: true
                  active: root.mode === modelData.id
                  hasCursor: root.cursorActive && root.focusSection === "mode" && root.selectedIndex === index
                  onClicked: root.setMode(modelData.id)
                  onHovered: function(h) {
                    if (h) {
                      root.cursorActive = true
                      root.focusSection = "mode"
                      root.selectedIndex = index
                    }
                  }
                }
              }
            }
          }

          FanSlider {
            id: cpuFanRow
            visible: root.installed
            width: parent.width
            title: "CPU FAN"
            rpm: root.fan0Rpm
            section: "cpu"
            value: root.cpuFan
            onPreview: function(v) { root.previewFan("cpu", v) }
            onCommit: root.commitFans()
          }

          FanSlider {
            id: gpuFanRow
            visible: root.installed
            width: parent.width
            title: "GPU FAN"
            rpm: root.fan1Rpm
            section: "gpu"
            value: root.gpuFan
            onPreview: function(v) { root.previewFan("gpu", v) }
            onCommit: root.commitFans()
          }

          PanelSeparator {
            visible: root.installed
            foreground: root.bar.foreground
          }

          Column {
            visible: root.installed
            width: parent.width
            spacing: Style.space(10)

            Toggle {
              id: battToggle
              width: parent.width
              label: "Charge limit"
              description: root.batteryOn ? (root.batteryLimit + "%") : "Off — charge to full"
              checked: root.batteryOn
              hasCursor: root.cursorActive && root.focusSection === "battery" && root.selectedIndex === 0
              foreground: root.bar.foreground
              onClicked: root.toggleBattery()
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.focusSection = "battery"
                  root.selectedIndex = 0
                }
              }
            }

            CursorSurface {
              visible: root.batteryOn
              width: parent.width
              height: battSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "battery" && root.selectedIndex === -1
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: battSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 20
                maximum: 100
                step: 5
                integer: true
                value: root.batteryLimit
                onMoved: function(v) { root.previewBattery(v) }
                onReleased: function(v) {
                  root.previewBatt = Model.clampBatt(v)
                  root.commitBattery()
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "battery"
                  root.selectedIndex = -1
                }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            wrapMode: Text.WordWrap
            color: bar && bar.urgent ? bar.urgent : Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component TempCell: Column {
    property string label: ""
    property int temp: 0
    spacing: Style.space(2)

    Text {
      text: label
      color: root.dim
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      text: temp > 0 ? (temp + "°") : "—"
      color: root.tempColor(temp)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  component FanSlider: Column {
    id: fanRoot
    property string title: ""
    property int rpm: 0
    property string section: ""
    property alias slider: sliderItem
    property int value: 0
    signal preview(real value)
    signal commit()

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(header.implicitHeight, rpmLabel.implicitHeight)

      PanelSectionHeader {
        id: header
        text: title
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: rpmLabel
        text: value + "%  ·  " + rpm + " rpm"
        color: root.dim
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      width: parent.width
      height: sliderItem.implicitHeight + Style.spacing.controlGap
      hasCursor: root.cursorActive && root.focusSection === section && root.selectedIndex === -1
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: sliderItem
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: 0
        maximum: 100
        step: 5
        integer: true
        value: fanRoot.value
        onMoved: function(v) { fanRoot.preview(v) }
        onReleased: function(v) { fanRoot.preview(v); fanRoot.commit() }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) {
          root.cursorActive = true
          root.focusSection = section
          root.selectedIndex = -1
        }
      }
    }
  }
}
