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

  function scheduleRestore() {
    restoreAttempt = 0
    restoreDelay.interval = 1000
    restoreDelay.restart()
  }

  function runRestore() {
    if (restoreProc.running) return
    restoreProc.command = [root.cli, "restore"]
    restoreProc.running = true
  }

  Process {
    id: sleepWatch
    running: true
    command: [
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

  Timer {
    id: restoreDelay
    interval: 1000
    repeat: false
    onTriggered: root.runRestore()
  }

  Process {
    id: restoreProc
    onExited: function(exitCode) {
      if (exitCode === 0) return
      root.restoreAttempt += 1
      if (root.restoreAttempt >= 12) return
      restoreDelay.interval = 500
      restoreDelay.restart()
    }
  }
}
