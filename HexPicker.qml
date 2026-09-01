import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "HexLayout.js" as HexLayout

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string mode: "themes"
  property string filterText: ""
  property int selectedIndex: 0
  property int wave: 0
  property int waveOrigin: 0
  property bool applying: false
  property int applyIndex: -1
  property bool waveOnLoad: false
  property bool galleryAnimating: false
  property string queuedMode: ""
  property string statusText: ""
  property int contextIndex: -1
  property var contextActions: []
  property int flippedIndex: -1
  property int paletteIndex: 0
  property int thumbRev: 0
  property int galleryFetchedAt: 0
  property var thumbOnDisk: ({})
  property var thumbQueue: []
  property var thumbMarkBuf: []
  property bool thumbBusy: false
  readonly property string cacheDir: {
    var home = Quickshell.env("HOME")
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    return (xdg && xdg.length ? xdg : (home + "/.cache")) + "/omarchy/grid-wallpaper-picker"
  }
  readonly property string thumbCacheDir: cacheDir + "/net"
  readonly property string galleryCachePath: cacheDir + "/gallery.json"
  property var items: []
  property var visibleItems: []
  property var cachedThemes: []
  property var cachedBackgrounds: []
  property var cachedGallery: []

  readonly property string pluginDir: {
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    return dir.replace(/\/$/, "")
  }
  readonly property string listScript: pluginDir + "/list.sh"
  readonly property string fetchGallery: pluginDir + "/bin/fetch-gallery.py"
  readonly property string applyGallery: pluginDir + "/bin/apply-gallery.py"

  property color foreground: Color.imagePicker.text
  property color scrim: Color.imagePicker.scrim
  property color dimColor: Color.background
  property color accent: Color.imagePicker.selectedBorder

  readonly property int chromeTop: Style.space(72)
  readonly property int chromeBottom: Style.space(88)
  readonly property int sidePad: Style.space(64)

  function normalizeMode(name) {
    var m = String(name || "")
    if (m === "wallpaper" || m === "wallpapers" || m === "background")
      return "backgrounds"
    if (m === "gallery" || m === "browse" || m === "store")
      return "gallery"
    if (m === "backgrounds")
      return "backgrounds"
    return "themes"
  }

  function nextModeName() {
    if (root.mode === "themes")
      return "backgrounds"
    if (root.mode === "backgrounds")
      return "gallery"
    return "themes"
  }

  function modeTitle() {
    if (root.mode === "backgrounds")
      return "Backgrounds"
    if (root.mode === "gallery")
      return "Gallery"
    return "Themes"
  }

  function cacheFor(modeName) {
    if (modeName === "backgrounds")
      return root.cachedBackgrounds
    if (modeName === "gallery")
      return root.cachedGallery
    return root.cachedThemes
  }

  function setCache(modeName, rows) {
    if (modeName === "backgrounds")
      root.cachedBackgrounds = rows
    else if (modeName === "gallery")
      root.cachedGallery = rows
    else
      root.cachedThemes = rows
  }

  function open(payloadJson) {
    var args = {}
    if (payloadJson) {
      try { args = JSON.parse(payloadJson) || {} } catch (e) { args = {} }
    }
    var nextMode = root.normalizeMode(args.mode || root.mode || "themes")
    root.hideMenu()
    root.mode = nextMode
    root.filterText = ""
    root.applying = false
    root.applyIndex = -1
    root.statusText = ""
    root.unflip()
    root.opened = true

    var cached = root.cacheFor(nextMode)
    if (cached.length > 0) {
      root.items = cached
      root.rebuildVisible()
      root.waveOrigin = root.selectedIndex
      root.wave += 1
      root.waveOnLoad = false
      if (nextMode === "gallery") {
        root.galleryAnimating = true
        galleryWaveTimer.restart()
      }
    } else {
      root.waveOnLoad = true
      if (nextMode === "gallery")
        root.statusText = "Fetching gallery…"
    }

    root.loadItems(nextMode)
    if (nextMode === "gallery")
      root.startPrefetch()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.applying = false
    root.applyIndex = -1
    root.hideMenu()
    root.unflip()
  }

  function dismiss() {
    root.opened = false
    root.applying = false
    root.applyIndex = -1
    root.hideMenu()
    root.unflip()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "rblalock.grid-wallpaper-picker")
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open('{"mode":"themes"}')
  }

  function loadItems(modeName) {
    var next = root.normalizeMode(modeName || root.mode)
    if (next === "gallery") {
      root.loadGallery()
      return
    }
    if (!root.listScript)
      return
    if (listProc.running) {
      root.queuedMode = next
      return
    }
    listProc.listMode = next
    listProc.command = ["bash", root.listScript, next]
    listProc.running = true
  }

  function loadGallery() {
    if (!root.fetchGallery)
      return
    if (galleryProc.running)
      return
    galleryProc.command = ["python3", root.fetchGallery]
    galleryProc.running = true
  }

  function applyRows(text, modeName) {
    var rows = HexLayout.parseRows(text)
    root.setCache(modeName, rows)
    if (modeName !== root.mode)
      return
    root.items = rows
    root.rebuildVisible()
    if (root.waveOnLoad && root.opened) {
      root.waveOrigin = root.selectedIndex
      root.wave += 1
      root.waveOnLoad = false
    }
  }

  function applyGalleryObject(obj) {
    if (!obj || !obj.entries)
      return
    var fetched = 0
    try { fetched = obj.fetchedAt || 0 } catch (e) { fetched = 0 }
    var rows = HexLayout.parseGallery(obj)
    if (rows.length === 0)
      return
    if (fetched && fetched === root.galleryFetchedAt && root.cachedGallery.length === rows.length)
      return

    var hadItems = root.cachedGallery.length > 0
    var flippedKey = ""
    if (root.flippedIndex >= 0 && root.flippedIndex < root.visibleItems.length)
      flippedKey = root.visibleItems[root.flippedIndex].key

    root.galleryFetchedAt = fetched
    root.cachedGallery = rows
    if (root.mode !== "gallery")
      return

    root.items = rows
    if (root.statusText === "Fetching gallery…")
      root.statusText = ""
    root.rebuildVisible(!(hadItems && !root.waveOnLoad))
    if (flippedKey) {
      var fi = HexLayout.indexOfKey(root.visibleItems, flippedKey)
      root.flippedIndex = (root.visibleItems[fi] && root.visibleItems[fi].key === flippedKey) ? fi : -1
    }
    if (root.waveOnLoad && root.opened) {
      root.waveOrigin = root.selectedIndex
      root.wave += 1
      root.waveOnLoad = false
      root.galleryAnimating = true
      galleryWaveTimer.restart()
    }
    root.startPrefetch()
  }

  function preload() {
    if (root.listScript)
      root.loadItems("themes")
  }

  function rebuildVisible(center) {
    var next = HexLayout.filterItems(root.items, root.filterText)
    var previousKey = ""
    if (root.visibleItems.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.visibleItems.length)
      previousKey = root.visibleItems[root.selectedIndex].key
    root.visibleItems = next
    root.selectedIndex = HexLayout.indexOfKey(next, previousKey)
    if (center !== false)
      Qt.callLater(root.centerOnSelected)
  }

  function setFilter(next) {
    root.filterText = next
    root.hideMenu()
    root.rebuildVisible()
  }

  function selectIndex(index) {
    if (root.visibleItems.length === 0)
      return
    if (index < 0)
      index = 0
    if (index >= root.visibleItems.length)
      index = root.visibleItems.length - 1
    root.selectedIndex = index
    root.centerOnSelected()
  }

  function selectNeighbor(dcol, drow) {
    root.selectIndex(HexLayout.neighborIndex(root.selectedIndex, hexList.columns, root.visibleItems.length, dcol, drow))
  }

  function currentItem() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleItems.length)
      return null
    return root.visibleItems[root.selectedIndex]
  }

  function switchMode() {
    root.open(JSON.stringify({ mode: root.nextModeName() }))
  }

  function unflip() {
    root.flippedIndex = -1
    root.paletteIndex = 0
  }

  function cyclePalette(delta) {
    var item = root.flippedIndex >= 0 ? root.visibleItems[root.flippedIndex] : null
    var n = item && item.variants ? item.variants.length : 0
    if (n <= 0)
      return
    root.paletteIndex = (root.paletteIndex + delta + n) % n
  }

  function applyFlipped() {
    var item = root.flippedIndex >= 0 ? root.visibleItems[root.flippedIndex] : root.currentItem()
    if (!item)
      return
    var v = (item.variants && item.variants[root.paletteIndex]) || {}
    root.installGalleryItem(item, {
      slug: v.slug || item.path,
      base: item.apply ? item.apply.base : "",
      ct: v.ct || "",
      bg: v.bg || "",
      label: item.label + " · " + (v.label || "Palette")
    })
    root.unflip()
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.visibleItems.length)
      return
    root.hideMenu()
    if (index !== root.selectedIndex) {
      root.unflip()
      root.selectIndex(index)
      return
    }
    if (root.mode === "gallery") {
      if (root.flippedIndex !== index) {
        root.flippedIndex = index
        root.paletteIndex = 0
      } else {
        root.applyFlipped()
      }
      return
    }
    root.applySelected()
  }

  function applySelected() {
    var item = root.currentItem()
    if (!item || root.applying)
      return

    root.applying = true
    root.applyIndex = root.selectedIndex
    root.hideMenu()

    if (root.mode === "gallery") {
      root.installGalleryItem(item, item.apply || {})
      return
    }

    var command = root.mode === "themes"
      ? "omarchy theme set " + Util.shellQuote(item.path)
      : "omarchy theme bg set " + Util.shellQuote(item.path)
    applyTimer.command = command
    applyTimer.restart()
    closeTimer.restart()
  }

  function installGalleryItem(item, spec) {
    spec = spec || {}
    root.applying = true
    root.applyIndex = root.selectedIndex
    root.hideMenu()
    root.statusText = "Installing " + (spec.label || item.label) + "…"
    galleryApplyProc.command = [
      "python3", root.applyGallery,
      String(spec.slug || item.path || ""),
      String(spec.base || (item.apply && item.apply.base) || ""),
      String(spec.ct || ""),
      String(spec.bg || ""),
      String((item.apply && item.apply.fallback) || item.key || "")
    ]
    galleryApplyProc.running = true
  }

  function deleteContextTheme() {
    var item = root.contextIndex >= 0 ? root.visibleItems[root.contextIndex] : root.currentItem()
    root.hideMenu()
    if (!item || !item.removable)
      return
    Util.execDetached("omarchy theme remove " + Util.shellQuote(item.path))
    root.statusText = "Removed " + item.label
    root.loadItems("themes")
  }

  function activateContext(index) {
    var action = root.contextActions[index]
    if (!action)
      return
    if (action.kind === "delete") {
      root.deleteContextTheme()
      return
    }
    if (action.kind === "variant") {
      var item = root.contextIndex >= 0 ? root.visibleItems[root.contextIndex] : root.currentItem()
      if (!item)
        return
      root.installGalleryItem(item, {
        slug: action.slug,
        base: item.apply ? item.apply.base : "",
        ct: action.ct,
        bg: action.bg,
        label: item.label + " · " + action.label
      })
    }
  }

  function openContextMenu(index, gx, gy) {
    if (index < 0 || index >= root.visibleItems.length)
      return
    var item = root.visibleItems[index]
    if (!item)
      return
    var actions = []
    if (root.mode === "themes" && item.removable)
      actions.push({ kind: "delete", label: "Delete" })
    if (root.mode === "gallery" && item.variants && item.variants.length) {
      for (var i = 0; i < item.variants.length; i++) {
        var v = item.variants[i]
        actions.push({
          kind: "variant",
          label: v.label,
          slug: v.slug,
          ct: v.ct,
          bg: v.bg
        })
      }
    }
    if (actions.length === 0)
      return
    root.selectedIndex = index
    root.contextIndex = index
    root.contextActions = actions
    contextMenu.x = Math.min(panel.width - 180, Math.max(12, gx))
    contextMenu.y = Math.min(panel.height - (actions.length * 36 + 16), Math.max(12, gy))
    contextMenu.visible = true
  }

  function hideMenu() {
    contextMenu.visible = false
    root.contextIndex = -1
    root.contextActions = []
  }

  function thumbPathFor(url) {
    return HexLayout.thumbDiskPath(url, root.thumbCacheDir)
  }

  function hasThumb(path) {
    return !!(path && root.thumbOnDisk[path])
  }

  function markThumb(path) {
    if (!path || root.thumbOnDisk[path])
      return
    root.thumbOnDisk[path] = true
    root.thumbRev += 1
  }

  function requestThumb(url) {
    // Gallery thumbs are filled by prefetch-thumbs.py; this is a no-op hook
    // so cells can still ask without starting serial HTTPS fetches.
    void url
  }

  function queueThumbMark(path) {
    if (!path)
      return
    root.thumbMarkBuf.push(path)
    thumbFlushTimer.restart()
  }

  function flushThumbMarks() {
    var buf = root.thumbMarkBuf
    if (!buf.length)
      return
    root.thumbMarkBuf = []
    for (var i = 0; i < buf.length; i++)
      root.thumbOnDisk[buf[i]] = true
    root.thumbRev += 1
  }

  function startPrefetch() {
    if (!root.pluginDir || prefetchProc.running)
      return
    prefetchProc.command = ["python3", root.pluginDir + "/bin/prefetch-thumbs.py"]
    prefetchProc.running = true
  }

  function indexThumbCache() {
    if (!root.thumbCacheDir)
      return
    thumbIndexProc.command = ["bash", "-c", "mkdir -p \"$0\"; find \"$0\" -type f -print", root.thumbCacheDir]
    thumbIndexProc.running = true
  }

  function centerOnSelected() {
    if (!hexList.height || root.visibleItems.length === 0)
      return
    var row = Math.floor(root.selectedIndex / Math.max(1, hexList.columns))
    hexList.positionViewAtIndex(row, ListView.Center)
  }

  function chromeHint() {
    if (root.statusText)
      return root.statusText
    if (root.filterText)
      return "filter: " + root.filterText + " · " + root.visibleItems.length
    if (root.mode === "gallery")
      return "Tab to switch · Enter flips hex · Enter again applies Palette"
    if (root.mode === "themes")
      return "Tab to switch · Enter to apply · Right-click to delete"
    return "Tab to switch · Enter to apply · Esc to close"
  }

  Process {
    id: listProc
    property string listMode: "themes"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRows(String(text || ""), listProc.listMode)
    }
    onExited: {
      var next = root.queuedMode
      if (!next)
        return
      root.queuedMode = ""
      root.loadItems(next)
    }
  }

  Process {
    id: galleryProc
    stdout: SplitParser {
      onRead: function(line) {
        var payload = {}
        try { payload = JSON.parse(String(line || "") || "{}") } catch (e) { return }
        if (!payload.ok) {
          if (root.cachedGallery.length === 0) {
            root.statusText = payload.error ? String(payload.error) : "Gallery fetch failed"
            root.waveOnLoad = false
          }
          return
        }
        if (payload.refreshed)
          galleryFile.reload()
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.mode === "gallery" && root.cachedGallery.length === 0)
        root.statusText = "Gallery fetch failed"
    }
  }

  Process {
    id: galleryApplyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = {}
        try { payload = JSON.parse(String(text || "") || "{}") } catch (e) { payload = {} }
        if (!payload.ok) {
          root.applying = false
          root.applyIndex = -1
          root.statusText = payload.error ? String(payload.error) : "Install failed"
          return
        }
        var slug = payload.slug || (root.currentItem() && root.currentItem().path) || ""
        if (slug)
          Util.execDetached("omarchy theme set " + Util.shellQuote(slug))
        closeTimer.restart()
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.applying) {
        root.applying = false
        root.applyIndex = -1
        if (!root.statusText)
          root.statusText = "Install failed"
      }
    }
  }

  FileView {
    id: galleryFile
    path: root.galleryCachePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        root.applyGalleryObject(JSON.parse(text() || "{}"))
      } catch (e) {
        if (root.cachedGallery.length === 0)
          root.statusText = "Could not read gallery index"
      }
    }
    onFileChanged: reload()
  }

  Process {
    id: prefetchProc
    stdout: SplitParser {
      onRead: function(line) {
        root.queueThumbMark(String(line || "").trim())
      }
    }
  }

  Timer {
    id: thumbFlushTimer
    interval: 32
    repeat: false
    onTriggered: root.flushThumbMarks()
  }

  Process {
    id: thumbIndexProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i])
            root.thumbOnDisk[lines[i]] = true
        }
        root.thumbRev += 1
      }
    }
  }

  onPluginDirChanged: {
    if (root.listScript)
      root.preload()
    root.indexThumbCache()
  }

  Timer {
    id: applyTimer
    property string command: ""
    interval: 140
    repeat: false
    onTriggered: {
      if (command)
        Util.execDetached(command)
    }
  }

  Timer {
    id: closeTimer
    interval: 240
    repeat: false
    onTriggered: root.dismiss()
  }

  Timer {
    id: galleryWaveTimer
    interval: 520
    repeat: false
    onTriggered: root.galleryAnimating = false
  }

  PanelWindow {
    id: panel
    visible: root.opened || scrim.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-grid-wallpaper-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: root.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      MouseArea {
        anchors.fill: parent
        enabled: root.opened && !root.applying
        onClicked: {
          if (contextMenu.visible)
            root.hideMenu()
          else
            root.dismiss()
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (!root.opened)
          return
        if (root.applying) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          if (contextMenu.visible)
            root.hideMenu()
          else if (root.flippedIndex >= 0)
            root.unflip()
          else if (root.filterText)
            root.setFilter("")
          else
            root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.unflip()
          root.switchMode()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (contextMenu.visible)
            root.activateContext(0)
          else
            root.activateIndex(root.selectedIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete && root.mode === "themes") {
          root.contextIndex = root.selectedIndex
          root.deleteContextTheme()
          event.accepted = true
        } else if (root.flippedIndex >= 0 && (event.key === Qt.Key_Left || event.key === Qt.Key_Up)) {
          root.cyclePalette(-1)
          event.accepted = true
        } else if (root.flippedIndex >= 0 && (event.key === Qt.Key_Right || event.key === Qt.Key_Down)) {
          root.cyclePalette(1)
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.unflip()
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.selectNeighbor(-1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.selectNeighbor(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectNeighbor(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectNeighbor(0, 1)
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.unflip()
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }
    }

    Column {
      id: chrome
      anchors.top: parent.top
      anchors.topMargin: Style.space(28)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.modeTitle()
        color: root.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.heading
        font.weight: Font.DemiBold
        style: Text.Outline
        styleColor: Util.alpha(root.dimColor, 0.7)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.chromeHint()
        color: Util.alpha(root.foreground, 0.72)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        style: Text.Outline
        styleColor: Util.alpha(root.dimColor, 0.7)
      }
    }

    ListView {
      id: hexList
      anchors.fill: parent
      anchors.topMargin: root.chromeTop
      anchors.bottomMargin: root.chromeBottom
      anchors.leftMargin: root.sidePad
      anchors.rightMargin: root.sidePad
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      pixelAligned: true
      reuseItems: false
      cacheBuffer: Math.round(height * 3)
      spacing: -(HexLayout.hexHeight(radius) - HexLayout.rowStep(radius))
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      readonly property int count: root.visibleItems.length
      readonly property real radius: HexLayout.fitRadius(count, Math.max(120, width), Math.max(120, height), root.mode === "gallery" ? 108 : 72, 124)
      readonly property int columns: HexLayout.columnsForWidth(Math.max(120, width), radius)
      readonly property var size: HexLayout.gridSize(count, columns, radius)
      readonly property int rowCount: Math.max(0, Math.ceil(count / Math.max(1, columns)))
      readonly property real xPad: Math.max(0, (width - size.width) / 2)
      readonly property int edgePad: Math.round(radius * 0.22) + 10

      displayMarginBeginning: edgePad
      displayMarginEnd: edgePad

      header: Item {
        width: hexList.width
        height: hexList.edgePad
      }
      footer: Item {
        width: hexList.width
        height: hexList.edgePad
      }

      model: rowCount

      delegate: Item {
        id: rowRoot
        required property int index
        width: hexList.width
        height: HexLayout.hexHeight(hexList.radius)
        z: index

        Repeater {
          model: hexList.columns

          HexCell {
            required property int index
            readonly property int itemIndex: rowRoot.index * hexList.columns + index
            item: itemIndex < root.visibleItems.length ? root.visibleItems[itemIndex] : null
            visible: item !== null
            radius: hexList.radius
            host: root
            scrolling: hexList.moving
            flipped: itemIndex === root.flippedIndex
            paletteIndex: root.paletteIndex
            selected: itemIndex === root.selectedIndex
            current: item ? item.current === true : false
            wave: root.wave
            waveIndex: itemIndex
            appearDelay: Math.min(HexLayout.hexDistance(itemIndex, root.waveOrigin, hexList.columns) * 28, 420)
            animateEnter: root.mode !== "gallery" || root.galleryAnimating
            exiting: root.applying
            applyTarget: root.applying && itemIndex === root.applyIndex
            accent: root.accent
            dimColor: root.dimColor
            x: hexList.xPad + HexLayout.position(itemIndex, hexList.columns, hexList.radius).x
            y: 0

            onClicked: root.activateIndex(itemIndex)
            onEntered: {
              if (root.applying)
                return
              if (root.flippedIndex >= 0 && itemIndex !== root.flippedIndex)
                return
              root.selectedIndex = itemIndex
            }
            onPalettePicked: function(i) {
              root.paletteIndex = i
              root.applyFlipped()
            }
            onContextRequested: function(gx, gy) {
              root.openContextMenu(itemIndex, gx, gy)
            }
          }
        }
      }

    }

    Text {
      id: selectedLabel
      visible: root.opened && !!root.currentItem()
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width - Style.space(80), Style.space(720))
      text: {
        var item = root.currentItem()
        if (!item)
          return ""
        if (root.flippedIndex >= 0 && item.variants && item.variants[root.paletteIndex])
          return item.label + " · " + item.variants[root.paletteIndex].label
        return item.label
      }
      color: root.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.display
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      style: Text.Outline
      styleColor: Util.alpha(root.dimColor, 0.7)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
      id: contextMenu
      visible: false
      width: Style.space(168)
      height: contextColumn.implicitHeight + Style.space(8)
      radius: Math.max(4, Style.cornerRadius)
      color: Color.menu.background
      border.width: 1
      border.color: Color.menu.border
      z: 200

      Column {
        id: contextColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)
        spacing: 0

        Repeater {
          model: root.contextActions.length
          Rectangle {
            required property int index
            width: contextColumn.width
            height: Style.space(32)
            radius: Math.max(3, Style.cornerRadius)
            color: actionMouse.containsMouse ? Color.menu.selectedBackground : "transparent"

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              text: root.contextActions[index] ? root.contextActions[index].label : ""
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activateContext(index)
            }
          }
        }
      }
    }
  }
}
