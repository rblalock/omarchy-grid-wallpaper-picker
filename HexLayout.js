.pragma library

var SQRT3 = 1.73205080757

function thumbDiskPath(url, cacheRoot) {
  var u = String(url || "")
  if (!cacheRoot || u.indexOf("https://") !== 0)
    return ""
  var path = u.replace(/^https:\/\/[^/]+\//, "")
  if (!path)
    return ""
  path = path.replace(/[^A-Za-z0-9._/-]/g, "_")
  return String(cacheRoot).replace(/\/$/, "") + "/" + path
}

function hexWidth(radius) {
  return radius * SQRT3
}

function hexHeight(radius) {
  return radius * 2
}

function rowStep(radius) {
  return radius * 1.5
}

function columnsForWidth(width, radius) {
  var w = hexWidth(radius)
  if (w <= 1)
    return 1
  return Math.max(1, Math.floor((width - w * 0.5) / w))
}

function position(index, columns, radius) {
  var cols = Math.max(1, columns)
  var col = index % cols
  var row = Math.floor(index / cols)
  var w = hexWidth(radius)
  return {
    x: col * w + (row % 2) * (w / 2),
    y: row * rowStep(radius),
    width: w,
    height: hexHeight(radius),
    col: col,
    row: row
  }
}

function gridSize(count, columns, radius) {
  if (count <= 0)
    return { width: 0, height: 0, rows: 0 }
  var cols = Math.max(1, columns)
  var rows = Math.ceil(count / cols)
  var w = hexWidth(radius)
  return {
    width: cols * w + w / 2,
    height: (rows - 1) * rowStep(radius) + hexHeight(radius),
    rows: rows
  }
}

function fitRadius(count, viewW, viewH, minR, maxR) {
  var lo = minR || 52
  var hi = maxR || 118
  var best = lo
  if (count <= 0 || viewW <= 0 || viewH <= 0)
    return Math.floor(hi)

  for (var i = 0; i < 14; i++) {
    var mid = (lo + hi) / 2
    var cols = columnsForWidth(viewW, mid)
    var size = gridSize(count, cols, mid)
    if (size.width <= viewW && size.height <= viewH) {
      best = mid
      lo = mid
    } else {
      hi = mid
    }
  }
  return Math.max(minR || 52, Math.floor(best))
}

function parseRows(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line)
      continue
    var cols = line.split("\t")
    if (cols.length < 4)
      continue
    out.push({
      key: cols[0],
      label: cols[1],
      path: cols[2],
      thumbnail: cols[3],
      current: cols[4] === "1",
      removable: cols[5] === "1",
      gallery: false
    })
  }
  return out
}

function matches(item, filterText) {
  if (!filterText)
    return true
  if (!item)
    return false
  var needle = String(filterText).toLowerCase()
  if (String(item.label || "").toLowerCase().indexOf(needle) !== -1)
    return true
  if (String(item.key || "").toLowerCase().indexOf(needle) !== -1)
    return true
  if (String(item.hay || "").indexOf(needle) !== -1)
    return true
  return false
}

var VARIANT_LABEL = {
  palette: "Palette",
  gruvbox: "Warm",
  nord: "Cool",
  material: "Material",
  aether: "Aether"
}

function parseGallery(obj) {
  if (!obj || !obj.entries)
    return []
  var base = String(obj.base || "").replace(/\/$/, "")
  var out = []
  for (var i = 0; i < obj.entries.length; i++) {
    var e = obj.entries[i]
    if (!e || !e.n)
      continue
    var thumbRel = e.thumb || e.p
    var tags = Array.isArray(e.tags) ? e.tags.join(" ") : ""
    var variants = []
    var vs = Array.isArray(e.vs) ? e.vs : []
    for (var j = 0; j < vs.length; j++) {
      var v = vs[j]
      if (!v || !v.n || !v.ct)
        continue
      variants.push({
        key: v.k || "",
        label: VARIANT_LABEL[v.k] || v.k || v.n,
        slug: v.n,
        ct: v.ct,
        bg: v.bg || ""
      })
    }
    if (variants.length === 0) {
      variants.push({
        key: "palette",
        label: "Palette",
        slug: e.n,
        ct: e.ct || "",
        bg: e.bg || ""
      })
    }
    out.push({
      key: e.p || e.n,
      label: e.t || e.n,
      path: e.n,
      thumbnail: thumbRel ? (base + "/" + thumbRel) : "",
      current: false,
      removable: false,
      gallery: true,
      hay: ((e.t || "") + " " + (e.p || "") + " " + tags).toLowerCase(),
      variants: variants,
      apply: {
        slug: e.n,
        base: base,
        ct: e.ct || "",
        bg: e.bg || "",
        fallback: e.p || ""
      }
    })
  }
  return out
}

function visibleRange(contentY, viewH, count, columns, radius, overscan) {
  overscan = overscan === undefined ? 2 : overscan
  if (count <= 0)
    return { first: 0, last: 0, count: 0 }
  var cols = Math.max(1, columns)
  var rs = rowStep(radius)
  if (rs <= 0)
    return { first: 0, last: Math.min(count, cols), count: Math.min(count, cols) }
  var rows = Math.ceil(count / cols)
  var firstRow = Math.floor(Math.max(0, contentY) / rs) - overscan
  if (firstRow < 0)
    firstRow = 0
  var lastRow = Math.ceil((Math.max(0, contentY) + Math.max(1, viewH)) / rs) + overscan
  if (lastRow >= rows)
    lastRow = rows - 1
  var first = firstRow * cols
  var last = Math.min(count, (lastRow + 1) * cols)
  return { first: first, last: last, count: Math.max(0, last - first) }
}

function filterItems(items, filterText) {
  if (!items || !items.length)
    return []
  if (!filterText)
    return items.slice()
  var out = []
  for (var i = 0; i < items.length; i++) {
    if (matches(items[i], filterText))
      out.push(items[i])
  }
  return out
}

function indexOfKey(items, key) {
  if (!items)
    return 0
  for (var i = 0; i < items.length; i++) {
    if (items[i].key === key)
      return i
  }
  for (var j = 0; j < items.length; j++) {
    if (items[j].current)
      return j
  }
  return 0
}

function offsetToCube(col, row) {
  var x = col - (row - (row & 1)) / 2
  var z = row
  var y = -x - z
  return { x: x, y: y, z: z }
}

function hexDistance(index, origin, columns) {
  var cols = Math.max(1, columns)
  var a = offsetToCube(index % cols, Math.floor(index / cols))
  var b = offsetToCube(origin % cols, Math.floor(origin / cols))
  return (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) + Math.abs(a.z - b.z)) / 2
}

function neighborIndex(index, columns, count, dcol, drow) {
  if (count <= 0)
    return 0
  var cols = Math.max(1, columns)
  var col = index % cols
  var row = Math.floor(index / cols)
  var nextCol = col + dcol
  var nextRow = row + drow
  if (nextCol < 0 || nextCol >= cols || nextRow < 0)
    return index
  var next = nextRow * cols + nextCol
  if (next < 0 || next >= count)
    return index
  return next
}
