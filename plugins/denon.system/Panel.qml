import "../denon.bar/panels" as Motion
import "data" as Data
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// System: one ring on the rail, the busiest of CPU, GPU and memory, matching
// the agents' rings; a letter under it says which. Disk is the lowest
// priority: it never takes the ring, but a disk 90 % full or more puts an
// urgent dot on it. Hover for the drawer: CPU (per thread), GPU, memory and
// disks, each with its last few minutes. Click the title for btop.
// Samples come from sample.py through data/Sampler.qml, shared by every rail.
Panel {
  id: root
  moduleName: "denon.system"
  ipcTarget: "denon.system"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color hair: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool tide: Motion.PanelMotion.tide

  readonly property real hot: 90         // a metric this high turns urgent
  readonly property real diskFull: 90    // a disk this full puts the dot on the ring

  // ---------------------------------------------------------------- samples
  // Shared by every rail (data/Sampler.qml), so there is one sample.py.
  readonly property var cpu: Data.Sampler.cpu
  readonly property var gpu: Data.Sampler.gpu
  readonly property var mem: Data.Sampler.mem
  readonly property var disks: Data.Sampler.disks
  readonly property var cpuHistory: Data.Sampler.cpuHistory
  readonly property var gpuHistory: Data.Sampler.gpuHistory
  readonly property var memHistory: Data.Sampler.memHistory
  readonly property int historyLength: Data.Sampler.historyLength

  readonly property real cpuPct: cpu ? cpu.total : -1
  readonly property real gpuPct: gpu && gpu.util !== null ? gpu.util : -1
  readonly property real memPct: mem && mem.total > 0 ? 100 * mem.used / mem.total : -1
  function diskPct(d) { return d.total > 0 ? 100 * d.used / d.total : 0 }
  readonly property var fullDisks: disks.filter(function(d) { return diskPct(d) >= root.diskFull })

  // The busiest live metric. Disk stays out of it.
  readonly property var busiest: {
    var best = { letter: "", name: "", value: -1 }
    var all = [["C", "CPU", cpuPct], ["G", "GPU", gpuPct], ["M", "Memory", memPct]]
    for (var i = 0; i < all.length; i++)
      if (all[i][2] > best.value) best = { letter: all[i][0], name: all[i][1], value: all[i][2] }
    return best
  }

  function gib(bytes) { return (bytes / 1073741824).toFixed(1) }
  function gb(bytes) { var g = bytes / 1e9; return g >= 100 ? Math.round(g) + " GB" : g.toFixed(1) + " GB" }
  function pct(v) { return v < 0 ? "–" : Math.round(v) }
  function mountName(m) { return m === "/" ? "System" : m.split("/").pop() || m }
  function openBtop() { root.close(); Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"]) }

  // ---------------------------------------------------------------- rail ring
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedHeight: button.vertical ? gaugeColumn.implicitHeight + Style.space(12) : -1
    fixedWidth: button.vertical ? -1 : gaugeColumn.implicitWidth + Style.space(16)
    active: root.busiest.value >= root.hot
    tooltipText: "CPU " + root.pct(root.cpuPct) + "% · GPU " + root.pct(root.gpuPct) + "% · Memory " + root.pct(root.memPct) + "%"
      + (root.fullDisks.length ? " · " + root.fullDisks.map(function(d) { return root.mountName(d.mount) + " disk " + Math.round(root.diskPct(d)) + "% full" }).join(", ") : "")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.openBtop()
      else if (!Motion.PanelMotion.commitHover(root)) root.toggle()
    }

    Column {
      id: gaugeColumn
      anchors.centerIn: parent
      spacing: Style.space(1)

      Item {
        width: Style.space(31); height: width
        readonly property color ringColor: root.busiest.value >= root.hot ? button.activeColor : button.foreground
        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.14)
            strokeWidth: Style.space(2.5); fillColor: "transparent"
            PathAngleArc { centerX: Style.space(15.5); centerY: Style.space(15.5); radiusX: Style.space(13); radiusY: Style.space(13); startAngle: 0; sweepAngle: 360 }
          }
          ShapePath {
            strokeColor: parent.parent.ringColor
            strokeWidth: Style.space(2.5); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: Style.space(15.5); centerY: Style.space(15.5); radiusX: Style.space(13); radiusY: Style.space(13); startAngle: -90; sweepAngle: 360 * Math.max(0, root.busiest.value) / 100 }
          }
        }
        Text {
          anchors.centerIn: parent
          text: root.pct(root.busiest.value)
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.space(10)
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
        }
        // A disk nearly full: a dot on the ring's shoulder.
        Rectangle {
          visible: root.fullDisks.length > 0
          width: Style.space(7); height: width; radius: width / 2
          color: root.urgent
          border.width: Style.space(1.5)
          border.color: Commons.Color.background
          x: parent.width - width + Style.space(1); y: -Style.space(1)
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.busiest.letter
        color: root.muted
        font.family: button.fontFamily
        font.pixelSize: Style.space(9)
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
      }
    }
  }

  // ---------------------------------------------------------------- pieces
  // The last few minutes as a soft line with a wash under it, 0–100 %.
  component Spark: Canvas {
    id: spark
    property var values: []
    property color tint: root.accent
    height: Style.space(30)
    onValuesChanged: requestPaint()
    onTintChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var n = values.length
      if (n < 2) return
      var step = width / (root.historyLength - 1)
      var x0 = width - (n - 1) * step
      var y = function(v) { return height - 1 - (height - 2) * Math.max(0, Math.min(100, v)) / 100 }
      ctx.beginPath()
      ctx.moveTo(x0, y(values[0]))
      for (var i = 1; i < n; i++) ctx.lineTo(x0 + i * step, y(values[i]))
      ctx.lineWidth = 1.5
      ctx.strokeStyle = tint
      ctx.stroke()
      ctx.lineTo(width, height)
      ctx.lineTo(x0, height)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.12)
      ctx.fill()
    }
  }

  // Name on the left, the value as a big light number on the right.
  component Header: Item {
    property string label: ""
    property string value: ""
    property string unit: "%"
    property bool alarm: false
    width: parent.width
    implicitHeight: Math.max(headerName.implicitHeight, headerNumber.implicitHeight)
    Text {
      id: headerName
      text: parent.label
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.space(14)
      font.weight: Font.Medium
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(5)
    }
    Text {
      id: headerNumber
      textFormat: Text.StyledText
      text: parent.value + "<span style='font-size:" + Style.space(14) + "px'>" + parent.unit + "</span>"
      color: parent.alarm ? root.urgent : root.accent
      font.family: root.family
      font.pixelSize: Style.space(28)
      font.weight: Font.ExtraLight
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component Detail: Text {
    leftPadding: Style.space(4)
    width: parent.width
    elide: Text.ElideRight
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.space(12)
  }

  // ---------------------------------------------------------------- drawer
  Motion.PopupPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(body.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: title.implicitHeight
          Text {
            id: title
            leftPadding: Style.space(4)
            text: "System"
            color: root.fg
            font.family: root.family
            font.pixelSize: root.tide ? Style.space(20) : Style.font.title + 1
            font.weight: root.tide ? Font.Light : Font.DemiBold
          }
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(24)
            width: btopLabel.implicitWidth + Style.space(18)
            radius: height / 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, btopMouse.containsMouse ? 0.1 : 0.05)
            border.width: 1
            border.color: root.hair
            Text { id: btopLabel; anchors.centerIn: parent; text: "btop  󰁔"; color: root.fg; font.family: root.family; font.pixelSize: Style.space(12) }
            MouseArea { id: btopMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openBtop() }
          }
        }

        // ---- CPU
        Column {
          visible: !!root.cpu
          width: parent.width
          spacing: Style.space(6)
          Header { label: "CPU"; value: root.pct(root.cpuPct); alarm: root.cpuPct >= root.hot }
          // One bar per thread.
          Row {
            id: coreRow
            width: parent.width
            height: Style.space(22)
            spacing: Style.space(2)
            readonly property var cores: root.cpu ? root.cpu.cores : []
            readonly property real barWidth: cores.length ? (width - spacing * (cores.length - 1)) / cores.length : 0
            Repeater {
              model: coreRow.cores
              Rectangle {
                required property var modelData
                width: coreRow.barWidth
                height: coreRow.height
                radius: Style.space(2)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(Style.space(2), parent.height * modelData / 100)
                  radius: Style.space(2)
                  color: modelData >= root.hot ? root.urgent : root.accent
                  Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
              }
            }
          }
          Spark { width: parent.width; values: root.cpuHistory }
          Detail {
            text: root.cpu ? [root.cpu.cores.length + " threads",
                              root.cpu.temp !== null && root.cpu.temp !== undefined ? Math.round(root.cpu.temp) + "°C" : "",
                              "load " + root.cpu.load.map(function(v) { return v.toFixed(1) }).join(" ")].filter(Boolean).join(" · ") : ""
          }
        }

        Motion.GlassSeparator { width: parent.width; foreground: root.fg; visible: !!root.gpu }

        // ---- GPU
        Column {
          visible: !!root.gpu
          width: parent.width
          spacing: Style.space(6)
          Header { label: "GPU"; value: root.pct(root.gpuPct); alarm: root.gpuPct >= root.hot }
          Spark { width: parent.width; values: root.gpuHistory }
          Detail {
            text: root.gpu ? [root.gpu.name,
                              root.gpu.memTotal ? (root.gpu.memUsed / 1024).toFixed(1) + " / " + (root.gpu.memTotal / 1024).toFixed(0) + " GiB VRAM" : "",
                              root.gpu.temp !== null ? Math.round(root.gpu.temp) + "°C" : "",
                              root.gpu.power !== null ? Math.round(root.gpu.power) + " W" : ""].filter(Boolean).join(" · ") : ""
          }
        }

        Motion.GlassSeparator { width: parent.width; foreground: root.fg }

        // ---- Memory
        Column {
          visible: !!root.mem
          width: parent.width
          spacing: Style.space(6)
          Header { label: "Memory"; value: root.pct(root.memPct); alarm: root.memPct >= root.hot }
          Spark { width: parent.width; values: root.memHistory }
          Detail {
            text: root.mem ? root.gib(root.mem.used) + " / " + root.gib(root.mem.total) + " GiB"
              + (root.mem.swapTotal > 0 ? " · swap " + root.gib(root.mem.swapUsed) + " / " + root.gib(root.mem.swapTotal) + " GiB" : "") : ""
          }
        }

        Motion.GlassSeparator { width: parent.width; foreground: root.fg; visible: root.disks.length > 0 }

        // ---- Disks
        Column {
          visible: root.disks.length > 0
          width: parent.width
          spacing: Style.space(10)
          Text {
            leftPadding: Style.space(4)
            text: "Disks"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.space(14)
            font.weight: Font.Medium
          }
          Repeater {
            model: root.disks
            Column {
              required property var modelData
              readonly property real used: root.diskPct(modelData)
              readonly property bool full: used >= root.diskFull
              width: parent.width
              spacing: Style.space(4)
              Item {
                width: parent.width
                implicitHeight: diskName.implicitHeight
                Text {
                  id: diskName
                  leftPadding: Style.space(4)
                  text: root.mountName(modelData.mount)
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.space(13)
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  text: root.gb(modelData.total - modelData.used) + " free of " + root.gb(modelData.total)
                  color: parent.parent.full ? root.urgent : root.muted
                  font.family: root.family
                  font.pixelSize: Style.space(12)
                }
              }
              Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                Rectangle {
                  width: parent.width * Math.min(1, parent.parent.used / 100)
                  height: parent.height
                  radius: height / 2
                  color: parent.parent.full ? root.urgent : root.accent
                }
              }
            }
          }
        }
      }
    }
  }
}
