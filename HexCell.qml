import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.Commons

Item {
  id: cell

  property real radius: 96
  property var item: null
  property bool selected: false
  property bool hovered: false
  property bool current: item ? item.current === true : false
  property bool appeared: false
  property bool exiting: false
  property bool applyTarget: false
  property int waveIndex: 0
  property int wave: 0
  property int appearDelay: 0
  property bool sourceActivated: false
  property bool animateEnter: true
  property bool scrolling: false
  property var host: null
  property color accent: Color.imagePicker.selectedBorder
  property color idleBorder: Color.imagePicker.unselectedBorder
  property color dimColor: Color.background

  readonly property real _r: radius
  readonly property real _cx: width / 2
  readonly property real _cy: height / 2
  readonly property real _cos30: 0.86602540378
  readonly property real _sin30: 0.5
  readonly property string thumbnail: item && item.thumbnail ? item.thumbnail : ""
  readonly property string itemKey: item && item.key ? item.key : ""
  readonly property string thumbSource: {
    var _rev = host && host.thumbRev
    if (!sourceActivated || !thumbnail)
      return ""
    var t = String(thumbnail)
    if (t.indexOf("https://") === 0) {
      var disk = host && host.thumbPathFor ? host.thumbPathFor(t) : ""
      if (disk && host.hasThumb && host.hasThumb(disk))
        return Util.fileUrl(disk)
      return ""
    }
    if (t.indexOf("http://") === 0 || t.indexOf("file:") === 0)
      return t
    return Util.fileUrl(t)
  }

  property real parallaxX: 0
  property real parallaxY: 0

  signal clicked()
  signal entered()
  signal contextRequested(real gx, real gy)

  width: _r * 1.73205080757
  height: _r * 2

  onWaveChanged: {
    if (!cell.animateEnter) {
      cell.appeared = true
      cell.sourceActivated = true
      return
    }
    appeared = false
    sourceActivated = false
    appearTimer.restart()
  }

  onItemKeyChanged: {
    if (cell.appeared)
      cell.sourceActivated = true
    cell.prefetchThumb()
  }

  function prefetchThumb() {
    if (!host || !host.requestThumb)
      return
    var t = String(thumbnail || "")
    if (t.indexOf("https://") === 0)
      host.requestThumb(t)
  }

  Timer {
    id: appearTimer
    interval: Math.max(1, cell.appearDelay)
    onTriggered: {
      cell.appeared = true
      cell.sourceActivated = true
    }
  }

  readonly property real visualScale: {
    if (cell.exiting && !cell.applyTarget)
      return 0.82
    if (!cell.appeared)
      return 0.76
    if (cell.applyTarget)
      return 1.12
    if (cell.selected)
      return 1.06
    if (cell.hovered)
      return 1.04
    return 1
  }

  readonly property real visualOpacity: {
    if (cell.exiting && !cell.applyTarget)
      return 0
    if (!cell.appeared)
      return 0
    return 1
  }

  scale: visualScale
  opacity: visualOpacity
  z: applyTarget ? 80 : (selected ? 40 : (hovered ? 20 : 1))
  transformOrigin: Item.Center
  transform: Translate {
    y: cell.appeared ? 0 : 14
    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
  }

  Behavior on scale {
    NumberAnimation {
      duration: cell.exiting || cell.applyTarget ? 180 : 240
      easing.type: Easing.OutCubic
    }
  }
  Behavior on opacity {
    NumberAnimation {
      duration: cell.exiting ? 140 : 220
      easing.type: Easing.OutCubic
    }
  }
  Behavior on parallaxX { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
  Behavior on parallaxY { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

  Component.onCompleted: {
    if (!cell.animateEnter) {
      cell.appeared = true
      cell.sourceActivated = true
    } else {
      appearTimer.restart()
    }
    cell.prefetchThumb()
  }

  Item {
    id: hexMask
    anchors.fill: parent
    visible: false
    layer.enabled: cell.appeared
    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "white"
        strokeColor: "transparent"
        startX: cell._cx
        startY: 0
        PathLine { x: cell._cx + cell._r * cell._cos30; y: cell._cy - cell._r * cell._sin30 }
        PathLine { x: cell._cx + cell._r * cell._cos30; y: cell._cy + cell._r * cell._sin30 }
        PathLine { x: cell._cx; y: cell.height }
        PathLine { x: cell._cx - cell._r * cell._cos30; y: cell._cy + cell._r * cell._sin30 }
        PathLine { x: cell._cx - cell._r * cell._cos30; y: cell._cy - cell._r * cell._sin30 }
        PathLine { x: cell._cx; y: 0 }
      }
    }
  }

  Item {
    id: imageLayer
    anchors.fill: parent
    layer.enabled: cell.appeared
    layer.smooth: !cell.scrolling
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: hexMask
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Rectangle {
      anchors.fill: parent
      color: cell.dimColor
    }

    Image {
      id: thumb
      width: cell.height * 1.28
      height: cell.height * 1.28
      x: (cell.width - width) / 2 + cell.parallaxX
      y: (cell.height - height) / 2 + cell.parallaxY
      source: cell.thumbSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: !cell.scrolling
      sourceSize.width: 256
      sourceSize.height: 256
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(cell.dimColor, cell.selected ? 0.08 : (cell.hovered ? 0.16 : 0.28))
      Behavior on color { ColorAnimation { duration: 180 } }
    }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "transparent"
      strokeColor: cell.selected ? cell.accent : (cell.hovered ? Util.alpha(cell.accent, 0.7) : cell.idleBorder)
      strokeWidth: cell.selected ? 3 : (cell.hovered ? 2 : 1.25)
      startX: cell._cx
      startY: 0
      PathLine { x: cell._cx + cell._r * cell._cos30; y: cell._cy - cell._r * cell._sin30 }
      PathLine { x: cell._cx + cell._r * cell._cos30; y: cell._cy + cell._r * cell._sin30 }
      PathLine { x: cell._cx; y: cell.height }
      PathLine { x: cell._cx - cell._r * cell._cos30; y: cell._cy + cell._r * cell._sin30 }
      PathLine { x: cell._cx - cell._r * cell._cos30; y: cell._cy - cell._r * cell._sin30 }
      PathLine { x: cell._cx; y: 0 }
    }
  }

  Rectangle {
    visible: cell.current
    width: 8
    height: 8
    radius: 4
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: cell._r * 0.22
    color: cell.accent
    border.width: 1
    border.color: Util.alpha(cell.dimColor, 0.7)
    z: 4
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    function contains(point) {
      var dx = Math.abs(point.x - cell._cx)
      var dy = Math.abs(point.y - cell._cy)
      return dx <= cell._cos30 * cell._r && dy <= cell._r - dx * 0.57735
    }
    onEntered: {
      cell.hovered = true
      cell.entered()
    }
    onExited: {
      cell.hovered = false
      cell.parallaxX = 0
      cell.parallaxY = 0
    }
    onPositionChanged: function(event) {
      cell.parallaxX = (event.x / width - 0.5) * 16
      cell.parallaxY = (event.y / height - 0.5) * 16
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var gp = cell.mapToItem(null, mouse.x, mouse.y)
        cell.contextRequested(gp.x, gp.y)
      } else {
        cell.clicked()
      }
    }
  }
}
