import "../denon.bar/panels" as Motion
import "../denon.audio" as Audio
import "../denon.audio/Model.js" as AudioModel
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Control: a drawer off the rail like Sound or Network, Control Center style.
// Six toggle tiles (Wi-Fi, Bluetooth, Do not disturb, Night light, Keep awake,
// Record), then Sound, Microphone and Display sliders, the power mode, and the
// battery on machines that have one. Left click a tile toggles it; right click
// opens that tool's full drawer. Push the pointer into the rail's bottom corner
// (denon.shell's hot corner) or use the sliders icon on the rail.
Panel {
  id: root
  moduleName: "denon.corner"
  ipcTarget: "denon.corner"
  implicitWidth: grip.implicitWidth
  implicitHeight: grip.implicitHeight

  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color hair: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color accent: Commons.Color.accent
  readonly property color accentInk: Commons.Color.popups.background
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool tide: Motion.PanelMotion.tide

  // ---------------------------------------------------------------- state
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: [root.sink, root.source].filter(function(x) { return !!x }) }
  readonly property real volume: sink && sink.audio ? Math.min(1, sink.audio.volume) : 0
  readonly property bool volumeMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real mic: source && source.audio ? Math.min(1, source.audio.volume) : 0
  readonly property bool micMuted: source && source.audio ? source.audio.muted : false

  // Devices to switch between, the same set the Sound drawer lists.
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var outputDevices: nodes.filter(function(n) { return n && n.isSink && !n.isStream })
  readonly property var inputDevices: nodes.filter(function(n) {
    return n && !n.isSink && !n.isStream && AudioModel.isAudioSource(n) && String(n.name || "") !== "quickshell"
  })
  property bool outputPickerOpen: false
  property bool inputPickerOpen: false

  // As the Sound drawer does it: Pipewire's preferred default plus Omarchy's
  // helper, which also moves playing streams and remembers the choice.
  function setOutput(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) Quickshell.execDetached(["omarchy-audio-output-set-default", String(node.id), String(node.name)])
    outputPickerOpen = false
  }
  function setInput(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) Quickshell.execDetached(["omarchy-audio-input-set-default", String(node.id), String(node.name)])
    inputPickerOpen = false
  }

  // Display brightness through Omarchy's own helper, which covers a laptop
  // panel, DDC monitors and Apple displays. -1 until read, and the slider
  // stays hidden when the focused display can't report one.
  property real brightness: -1
  readonly property bool hasBrightness: brightness >= 0

  // Battery only on machines that have one; a desktop gets no battery row.
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isLaptopBattery && battery.isPresent
  readonly property real batteryLevel: {
    var p = battery ? battery.percentage : 0
    return p > 1 ? p / 100 : p
  }
  readonly property bool charging: battery ? battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged : false
  readonly property string timeLeft: {
    var s = battery ? (charging ? battery.timeToFull : battery.timeToEmpty) : 0
    if (!s || s <= 0) return ""
    var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
    return (h > 0 ? h + " h " : "") + m + " m"
  }

  // Monitors, on or off for this session (displays.sh; monitors.lua is never
  // written). [{ name, desc, model, width, height, hz, on }]
  property var displays: []
  readonly property int displaysOn: displays.filter(function(d) { return d.on }).length
  readonly property string displaysScript: String(Qt.resolvedUrl("displays.sh")).replace(/^file:\/\//, "")
  // A tile's name: "Built-in" for a laptop panel, else the kind ("Ultrawide",
  // "4K", "1440p") when no other display shares it, else the model. Displays
  // compare by connector name: the Repeater hands each tile a copy.
  function displayKind(d) {
    if (/^(eDP|LVDS|DSI)-/.test(d.name)) return "Built-in"
    var ratio = d.height > 0 ? d.width / d.height : 0
    return ratio > 2.1 ? "Ultrawide" : d.width >= 3840 ? "4K" : d.width >= 2560 ? "1440p" : ""
  }
  function displayLabel(d) {
    var kind = displayKind(d)
    var sharedKind = displays.some(function(o) { return o.name !== d.name && displayKind(o) === kind })
    return kind && !sharedKind ? kind : d.model
  }
  // Same label and same model (two identical monitors): add the connector.
  function displayAmbiguous(d) {
    var label = displayLabel(d)
    return displays.some(function(o) { return o.name !== d.name && displayLabel(o) === label })
  }
  function setDisplay(d, on) {
    if (!on && d.on && displaysOn <= 1) return
    Quickshell.execDetached([displaysScript, on ? "on" : "off", d.desc])
    refreshDisplaysSoon.restart()
  }
  function onlyDisplay(d) {
    Quickshell.execDetached([displaysScript, "only", d.desc])
    refreshDisplaysSoon.restart()
  }
  Timer { id: refreshDisplaysSoon; interval: 900; onTriggered: if (!displaysRead.running) displaysRead.running = true }
  Process {
    id: displaysRead
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.displays = JSON.parse(text).map(function(m) {
            return { name: m.name, desc: m.description, model: m.model || m.name, width: m.width, height: m.height,
                     hz: Math.round(m.refreshRate || 0), on: !m.disabled }
          }).sort(function(a, b) { return a.name < b.name ? -1 : 1 })
        } catch (e) { }
      }
    }
  }

  property bool wifiOn: true
  property bool hasWifi: true
  property bool btOn: true
  property bool nightOn: false
  property bool dndOn: false
  property bool awakeOn: false
  property string profile: "balanced"
  readonly property var profiles: ["power-saver", "balanced", "performance"]

  onOpenedChanged: {
    if (opened) refresh()
    else { outputPickerOpen = false; inputPickerOpen = false }
  }
  Timer { interval: 4000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  function refresh() {
    if (!stateRead.running) stateRead.running = true
    if (!displaysRead.running) displaysRead.running = true
  }
  function run(cmd) { Quickshell.execDetached(cmd); refreshSoon.restart() }
  Timer { id: refreshSoon; interval: 450; onTriggered: root.refresh() }
  function openFull(target) { root.close(); Quickshell.execDetached(["omarchy-shell", target, "open"]) }
  function focusedMonitor() { return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" }

  Process {
    id: stateRead
    command: ["sh", "-c",
      "echo wifi=$(nmcli radio wifi 2>/dev/null);" +
      "echo wifidev=$(nmcli -t -f TYPE device 2>/dev/null | grep -cx wifi);" +
      "echo bt=$(bluetoothctl show 2>/dev/null | sed -n 's/.*Powered: //p' | head -1);" +
      "echo night=$(omarchy toggle nightlight --status 2>/dev/null | grep -o '\"enabled\":[a-z]*' | cut -d: -f2);" +
      "echo dnd=$(omarchy-shell notifications isDnd 2>/dev/null);" +
      "echo awake=$(test -e \"$HOME/.local/state/omarchy/indicators/stay-awake\" && echo on || echo off);" +
      "echo profile=$(powerprofilesctl get 2>/dev/null);" +
      "m=\"$1\"; echo bright=$(omarchy-brightness-display --no-osd ${m:+--monitor \"$m\"} 2>/dev/null | head -1 | tr -dc '0-9')",
      "sh", root.focusedMonitor()]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var kv = lines[i].split("="), k = kv[0], v = (kv[1] || "").trim()
          if (k === "wifi") root.wifiOn = v === "enabled"
          else if (k === "wifidev") root.hasWifi = Number(v) > 0
          else if (k === "bt") root.btOn = v === "yes"
          else if (k === "night") root.nightOn = v === "true"
          else if (k === "dnd") root.dndOn = v === "on"
          else if (k === "awake") root.awakeOn = v === "on"
          else if (k === "profile" && v) root.profile = v
          else if (k === "bright" && !displaySlider.dragging) root.brightness = v === "" ? -1 : Math.max(0, Math.min(1, Number(v) / 100))
        }
      }
    }
  }

  function setBrightness(f) {
    brightness = Math.max(0.01, Math.min(1, f))
    var mon = focusedMonitor()
    var cmd = ["omarchy-brightness-display", "--no-osd"]
    if (mon) cmd = cmd.concat(["--monitor", mon])
    Quickshell.execDetached(cmd.concat([Math.round(brightness * 100) + "%"]))
  }
  function setVolume(f) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, f)) } }
  function setMic(f) { if (source && source.audio) { source.audio.muted = false; source.audio.volume = Math.max(0, Math.min(1, f)) } }
  function toggleVolumeMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
  function toggleMicMute() { if (source && source.audio) source.audio.muted = !source.audio.muted }
  function setProfile(p) { profile = p; run(["powerprofilesctl", "set", p]) }
  function profileLabel(p) { return p === "power-saver" ? "Saver" : p === "performance" ? "Performance" : "Balanced" }

  // ---------------------------------------------------------------- rail icon
  // A plain glyph like its neighbours. The battery shows in the tooltip on a
  // laptop; the icon turns into a bolt while charging.
  WidgetButton {
    id: grip
    anchors.fill: parent
    bar: root.bar
    text: root.hasBattery && root.charging ? "󱐋" : "󰙪"
    tooltipText: "Control" + (root.hasBattery ? " · " + Math.round(root.batteryLevel * 100) + "%" + (root.timeLeft ? " · " + root.timeLeft : "") : "")
    onPressed: function(buttonCode) {
      if (!Motion.PanelMotion.commitHover(root)) root.toggle()
    }
  }

  // ---------------------------------------------------------------- pieces
  // A toggle tile: icon over a name and its state. Accent fill when on.
  component Tile: Rectangle {
    id: tile
    property string glyph: ""
    property string label: ""
    property string status: ""
    property bool on: false
    property string tip: ""
    signal flip()
    signal more()
    height: Style.space(68)
    radius: Style.space(14)
    color: on ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, tileMouse.containsMouse ? 0.1 : 0.05)
    border.width: on ? 0 : 1
    border.color: root.hair
    scale: tileMouse.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Text {
      x: Style.space(11); y: Style.space(9)
      text: tile.glyph
      color: tile.on ? root.accentInk : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.space(17)
    }
    Column {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(11); anchors.rightMargin: Style.space(8); anchors.bottomMargin: Style.space(8)
      spacing: 0
      Text {
        width: parent.width
        text: tile.label
        elide: Text.ElideRight
        color: tile.on ? root.accentInk : root.fg
        font.family: root.family
        font.pixelSize: Style.space(12)
        font.weight: Font.DemiBold
      }
      Text {
        width: parent.width
        text: tile.status
        elide: Text.ElideRight
        color: tile.on ? Qt.rgba(root.accentInk.r, root.accentInk.g, root.accentInk.b, 0.7) : root.muted
        font.family: root.family
        font.pixelSize: Style.space(11)
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { if (mouse.button === Qt.RightButton) tile.more(); else tile.flip() }
    }
    PanelToolTip { visible: tileMouse.containsMouse && tile.tip !== ""; text: tile.tip; fontFamily: root.family }
  }

  // A labelled level with the big light number the Sound drawer uses.
  component LevelHeader: Item {
    property string label: ""
    property real value: 0
    property bool dim: false
    signal labelClicked()
    width: parent.width
    implicitHeight: Math.max(levelName.implicitHeight, levelNumber.implicitHeight)
    Text {
      id: levelName
      text: parent.label
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.space(14)
      font.weight: Font.Medium
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(5)
      MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.labelClicked() }
    }
    Text {
      id: levelNumber
      textFormat: Text.StyledText
      text: Math.round(parent.value * 100) + "<span style='font-size:" + Style.space(14) + "px'>%</span>"
      color: parent.dim ? root.muted : root.accent
      font.family: root.family
      font.pixelSize: Style.space(28)
      font.weight: Font.ExtraLight
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // The current device as a small chip under a slider; click to unfold the
  // other devices in place and pick one.
  component DevicePicker: Column {
    id: picker
    property var devices: []
    property var current: null
    property bool open: false
    property bool input: false
    signal toggled()
    signal picked(var node)
    width: parent.width
    spacing: Style.space(2)

    function glyphFor(n) { return picker.input ? AudioModel.sourceGlyph(n) : AudioModel.sinkGlyph(n) }
    function same(a, b) { return !!a && !!b && a.id === b.id }

    Rectangle {
      id: chip
      height: Style.space(26)
      width: Math.min(picker.width, chipRow.implicitWidth + Style.space(20))
      radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, chipMouse.containsMouse || picker.open ? 0.1 : 0.05)
      border.width: 1
      border.color: root.hair
      Row {
        id: chipRow
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(10)
        spacing: Style.space(6)
        Text { anchors.verticalCenter: parent.verticalCenter; text: picker.glyphFor(picker.current); color: root.muted; font.family: Style.font.family; font.pixelSize: Style.space(12) }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, picker.width - Style.space(60))
          elide: Text.ElideRight
          text: picker.current ? AudioModel.nodeLabel(picker.current) : "No device"
          color: root.fg; font.family: root.family; font.pixelSize: Style.space(12)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅀"
          rotation: picker.open ? 180 : 0
          Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          color: root.muted; font.family: Style.font.family; font.pixelSize: Style.space(11)
        }
      }
      MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: picker.devices.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (picker.devices.length > 1) picker.toggled()
      }
    }

    Column {
      visible: picker.open
      width: parent.width
      topPadding: Style.space(4)
      spacing: Style.space(1)
      Repeater {
        model: picker.open ? picker.devices : []
        Rectangle {
          required property var modelData
          readonly property bool chosen: picker.same(modelData, picker.current)
          width: picker.width
          height: Style.space(34)
          radius: Style.space(10)
          color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(10)
            spacing: Style.space(10)
            Text { anchors.verticalCenter: parent.verticalCenter; width: Style.space(16); text: picker.glyphFor(modelData); color: chosen ? root.accent : root.muted; font.family: Style.font.family; font.pixelSize: Style.space(14) }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: picker.width - Style.space(70)
              elide: Text.ElideRight
              text: AudioModel.nodeLabel(modelData)
              color: chosen ? root.accent : root.fg
              font.family: root.family; font.pixelSize: Style.space(13)
              font.weight: chosen ? Font.DemiBold : Font.Normal
            }
          }
          Text {
            visible: chosen
            anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
            text: "󰄬"; color: root.accent; font.family: Style.font.family; font.pixelSize: Style.space(14)
          }
          MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.picked(modelData) }
        }
      }
    }
  }

  // ---------------------------------------------------------------- drawer
  Motion.PopupPanel {
    id: popup
    anchorItem: grip
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: popup.fittedContentWidth(Style.space(360))
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

        Text {
          leftPadding: Style.space(4)
          text: "Control"
          color: root.fg
          font.family: root.family
          font.pixelSize: root.tide ? Style.space(20) : Style.font.title + 1
          font.weight: root.tide ? Font.Light : Font.DemiBold
        }

        Grid {
          id: tiles
          width: parent.width
          columns: 3
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)
          readonly property real cell: (width - columnSpacing * 2) / 3

          Tile {
            width: tiles.cell
            glyph: root.hasWifi ? (root.wifiOn ? "󰖩" : "󰖪") : "󰈀"
            label: root.hasWifi ? "Wi-Fi" : "Network"
            status: root.hasWifi ? (root.wifiOn ? "On" : "Off") : "Wired"
            on: root.hasWifi && root.wifiOn
            tip: "Right-click for networks"
            onFlip: if (root.hasWifi) { root.wifiOn = !root.wifiOn; root.run(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"]) } else root.openFull("omarchy.network")
            onMore: root.openFull("omarchy.network")
          }
          Tile {
            width: tiles.cell
            glyph: root.btOn ? "󰂯" : "󰂲"
            label: "Bluetooth"
            status: root.btOn ? "On" : "Off"
            on: root.btOn
            tip: "Right-click for devices"
            onFlip: { root.btOn = !root.btOn; root.run(["bluetoothctl", "power", root.btOn ? "on" : "off"]) }
            onMore: root.openFull("omarchy.bluetooth")
          }
          Tile {
            width: tiles.cell
            glyph: root.dndOn ? "󰂛" : "󰂚"
            label: "Do not disturb"
            status: root.dndOn ? "On" : "Off"
            on: root.dndOn
            tip: "Right-click for notifications"
            onFlip: { root.dndOn = !root.dndOn; root.run(["omarchy-toggle-notification-silencing"]) }
            onMore: root.openFull("omarchy.notifications")
          }
          Tile {
            width: tiles.cell
            glyph: "󰖔"
            label: "Night light"
            status: root.nightOn ? "On" : "Off"
            on: root.nightOn
            tip: "Right-click for display"
            onFlip: { root.nightOn = !root.nightOn; root.run(["omarchy", "toggle", "nightlight"]) }
            onMore: root.openFull("omarchy.monitor")
          }
          Tile {
            width: tiles.cell
            glyph: "󰅶"
            label: "Keep awake"
            status: root.awakeOn ? "On" : "Off"
            on: root.awakeOn
            onFlip: { root.awakeOn = !root.awakeOn; root.run(["omarchy", "toggle", "idle", "toggle"]) }
          }
          Tile {
            width: tiles.cell
            glyph: "󰑊"
            label: "Record"
            status: "Screen"
            on: false
            onFlip: { root.close(); Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.global(\"snip:record\")"]) }
          }
        }

        Motion.GlassSeparator { width: parent.width; foreground: root.fg }

        Column {
          width: parent.width
          spacing: Style.space(4)
          LevelHeader { label: "Sound"; value: soundSlider.dragging ? soundSlider.liveValue : root.volume; dim: root.volumeMuted; onLabelClicked: root.openFull("omarchy.audio") }
          Audio.BigSlider {
            id: soundSlider
            bar: root.bar
            width: parent.width
            glyph: root.volumeMuted ? "󰝟" : "󰕾"
            muted: root.volumeMuted
            value: root.volume
            enabled: !!root.sink
            onMoved: function(v) { root.setVolume(v) }
            onRightClicked: root.toggleVolumeMute()
          }
          DevicePicker {
            devices: root.outputDevices
            current: root.sink
            open: root.outputPickerOpen
            onToggled: { root.outputPickerOpen = !root.outputPickerOpen; root.inputPickerOpen = false }
            onPicked: function(node) { root.setOutput(node) }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          LevelHeader { label: "Microphone"; value: micSlider.dragging ? micSlider.liveValue : root.mic; dim: root.micMuted; onLabelClicked: root.openFull("omarchy.audio") }
          Audio.BigSlider {
            id: micSlider
            bar: root.bar
            width: parent.width
            glyph: root.micMuted ? "󰍭" : "󰍬"
            muted: root.micMuted
            value: root.mic
            enabled: !!root.source
            onMoved: function(v) { root.setMic(v) }
            onRightClicked: root.toggleMicMute()
          }
          DevicePicker {
            input: true
            devices: root.inputDevices
            current: root.source
            open: root.inputPickerOpen
            onToggled: { root.inputPickerOpen = !root.inputPickerOpen; root.outputPickerOpen = false }
            onPicked: function(node) { root.setInput(node) }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.hasBrightness
          LevelHeader { label: "Display"; value: displaySlider.dragging ? displaySlider.liveValue : Math.max(0, root.brightness); onLabelClicked: root.openFull("omarchy.monitor") }
          Audio.BigSlider {
            id: displaySlider
            bar: root.bar
            width: parent.width
            glyph: "󰃟"
            value: Math.max(0, root.brightness)
            minimum: 0.01
            onMoved: function(v) { root.setBrightness(v) }
          }
        }

        // Which monitors are on. Left click switches one; right click keeps
        // only that one (say, the ultrawide for a game).
        Column {
          visible: root.displays.length > 1
          width: parent.width
          spacing: Style.space(8)
          Text {
            leftPadding: Style.space(4)
            text: "Displays"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.space(14)
            font.weight: Font.Medium
          }
          // Two side by side; three or more wrap three to a row like the toggles.
          Grid {
            id: displayRow
            width: parent.width
            columns: Math.max(1, Math.min(3, root.displays.length))
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)
            readonly property real cell: (width - columnSpacing * (columns - 1)) / columns
            Repeater {
              model: root.displays
              Tile {
                required property var modelData
                readonly property bool last: modelData.on && root.displaysOn <= 1
                width: displayRow.cell
                glyph: "󰍹"
                label: root.displayLabel(modelData)
                status: (root.displayAmbiguous(modelData) ? modelData.name + " · " : "") + (modelData.on ? (modelData.hz ? modelData.hz + " Hz" : "On") : "Off")
                on: modelData.on
                tip: modelData.model + (last ? " · the only display on" : " · right-click to use only this one")
                onFlip: root.setDisplay(modelData, !modelData.on)
                onMore: root.onlyDisplay(modelData)
              }
            }
          }
        }

        Motion.GlassSeparator { width: parent.width; foreground: root.fg }

        Motion.GlassTrack {
          width: parent.width
          foreground: root.fg

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(2)
            readonly property real cellWidth: (width - spacing * (root.profiles.length - 1)) / root.profiles.length

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                width: profileRow.cellWidth
                text: root.profileLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.family
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(1)
                bordered: false
                active: root.profile === modelData
                onClicked: root.setProfile(String(modelData))
              }
            }
          }
        }

        Item {
          visible: root.hasBattery
          width: parent.width
          implicitHeight: batteryText.implicitHeight
          Text {
            id: batteryText
            leftPadding: Style.space(4)
            text: (root.charging ? "Charging" : "Battery") + " · " + Math.round(root.batteryLevel * 100) + "%" + (root.timeLeft ? " · " + root.timeLeft : "")
            color: root.batteryLevel <= 0.2 && !root.charging ? Commons.Color.urgent : root.muted
            font.family: root.family
            font.pixelSize: Style.space(12)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openFull("omarchy.power") }
          }
        }
      }
    }
  }
}
