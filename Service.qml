import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir)
      return String(manifest.__sourceDir).replace(/\/$/, "")
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return url.replace(/\/$/, "")
  }
  readonly property string cli: pluginDir + "/omaerofan"

  property int restoreAttempt: 0
  property int syncAttempt: 0

  function scheduleRestore() {
    restoreAttempt = 0
    restoreDelay.interval = 1000
    restoreDelay.restart()
  }

  function scheduleSync() {
    syncDebounce.restart()
  }

  function runRestore() {
    if (restoreProc.running) return
    restoreProc.command = [root.cli, "restore"]
    restoreProc.running = true
  }

  function runSync() {
    if (syncProc.running || restoreProc.running) {
      syncDebounce.restart()
      return
    }
    syncProc.command = [root.cli, "sync"]
    syncProc.running = true
  }

  function runCurve() {
    if (curveProc.running || restoreProc.running) return
    curveProc.command = [root.cli, "apply-curve"]
    curveProc.running = true
  }

  Component.onCompleted: {
    root.scheduleRestore()
    root.scheduleSync()
  }

  Process {
    id: sleepWatch
    running: true
    command: [
      "stdbuf", "-oL",
      "dbus-monitor",
      "--system",
      "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
    ]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("boolean false") >= 0)
          root.scheduleRestore()
      }
    }
  }

  Process {
    id: profileWatch
    running: true
    command: [
      "stdbuf", "-oL",
      "dbus-monitor",
      "--system",
      "type='signal',path='/org/freedesktop/UPower/PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"
    ]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("ActiveProfile") >= 0)
          root.scheduleSync()
      }
    }
  }

  Timer {
    id: restoreDelay
    interval: 1000
    repeat: false
    onTriggered: root.runRestore()
  }

  Timer {
    id: syncDebounce
    interval: 250
    repeat: false
    onTriggered: root.runSync()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.scheduleSync()
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runCurve()
  }

  Process { id: curveProc }

  Process {
    id: restoreProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.restoreAttempt = 0
        return
      }
      root.restoreAttempt += 1
      if (root.restoreAttempt >= 12) return
      restoreDelay.interval = 500
      restoreDelay.restart()
    }
  }

  Process {
    id: syncProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.syncAttempt = 0
        return
      }
      root.syncAttempt += 1
      if (root.syncAttempt >= 8) return
      syncDebounce.interval = 750
      syncDebounce.restart()
    }
  }
}
