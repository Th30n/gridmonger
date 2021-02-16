import options
import strformat

import koi/undomanager

import common
import level
import links
import map
import rect
import selection
import tables
import utils


type UndoStateData* = object
  actionName*: string
  location*: Location

using
  map: var Map
  m:   var Map
  um:  var UndoManager[Map, UndoStateData]

# {{{ cellAreaAction()
template cellAreaAction(map; loc: Location, rect: Rect[Natural];
                        um; groupWithPrev: bool,
                        actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(
    actionName: actName,
    location: loc
  )

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    actionMap.levels[loc.level].reindexNotes()
    result = usd

  var oldLinks = map.links.filterByInRect(loc.level, rect)

  let undoLevel = newLevelFrom(map.levels[loc.level], rect)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level].copyCellsAndAnnotationsFrom(
      destRow = rect.r1,
      destCol = rect.c1,
      src     = undoLevel,
      srcRect = rectN(0, 0, undoLevel.rows, undoLevel.cols)
    )
    m.levels[loc.level].reindexNotes()

    # Delete existing links in undo area
    let delRect = rectN(
      rect.r1,
      rect.c1,
      rect.r1 + undoLevel.rows,
      rect.c1 + undoLevel.cols
    )
    for src in m.links.filterByInRect(loc.level, delRect).keys:
      m.links.delBySrc(src)

    m.links.addAll(oldLinks)
    result = usd

  um.storeUndoState(action, undoAction, groupWithPrev)
  discard action(map)

# }}}
# {{{ singleCellAction()
template singleCellAction(map; loc: Location; um;
                          actionName: string; actionMap, actionBody: untyped) =
  let
    c = loc.col
    r = loc.row
    cellRect = rectN(r, c, r+1, c+1)

  cellAreaAction(map, loc, cellRect, um, groupWithPrev=false,
                 actionName, actionMap, actionBody)

# }}}

# {{{ setWall*()
proc setWall*(map; loc: Location, dir: CardinalDir, w: Wall; um) =

  singleCellAction(map, loc, um, fmt"Set wall {EnDash} {w}", m):
    m.setWall(loc, dir, w)

# }}}
# {{{ drawClearFloor*()
proc drawClearFloor*(map; loc: Location, floorColor: byte; um) =

  singleCellAction(map, loc, um, fmt"Draw/clear floor", m):
    alias(l, m.levels[loc.level])
    l.delAnnotation(loc.row, loc.col)

    m.setFloor(loc, fBlank)
    m.setFloorColor(loc, floorColor)

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(map; loc: Location, floorColor: byte; um) =

  singleCellAction(map, loc, um, fmt"Set floor color {EnDash} {floorColor}", m):
    m.setFloorColor(loc, floorColor)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(map; loc: Location, f: Floor, ot: Orientation,
                       floorColor: byte; um) =

  singleCellAction(map, loc, um, fmt"Set floor {EnDash} {f}", m):
    m.setFloor(loc, f)
    m.setFloorOrientation(loc, ot)

    if m.isEmpty(loc):
      m.setFloorColor(loc, floorColor)

# }}}
# {{{ eraseCellWalls*()
proc eraseCellWalls*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell walls", m):
    m.eraseCellWalls(loc)

# }}}
# {{{ eraseCell*()
proc eraseCell*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell", m):
    m.eraseCell(loc)

# }}}
# {{{ excavate*()
proc excavate*(map; loc: Location, floorColor: byte; um) =
  singleCellAction(map, loc, um, "Excavate tunnel", m):
    m.excavate(loc, floorColor)

# }}}
# {{{ excavateTrail*()
proc excavateTrail*(map; loc: Location, bbox: Rect[Natural], floorColor: byte;
                    um) =

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false, "Excavate trail", m):
    var loc = loc

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        loc.row = r
        loc.col = c
        if m.hasTrail(loc):
          m.excavate(loc, floorColor)

# }}}
# {{{ clearTrail*()
proc clearTrail*(map; loc: Location, bbox: Rect[Natural], um) =

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false, "Clear trail", m):
    var loc = loc

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        loc.row = r
        loc.col = c
        m.setTrail(loc, false)

# }}}
# {{{ toggleFloorOrientation*()
proc toggleFloorOrientation*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Toggle floor orientation", m):
    let newOt = if m.getFloorOrientation(loc) == Horiz: Vert else: Horiz
    m.setFloorOrientation(loc, newOt)

# }}}
# {{{ setNote*()
proc setNote*(map; loc: Location, n: Annotation; um) =

  singleCellAction(map, loc, um, "Set note", m):
    alias(l, m.levels[loc.level])
    if n.kind != akComment:
      m.setFloor(loc, fBlank)

    l.setAnnotation(loc.row, loc.col, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Erase note", m):
    alias(l, m.levels[loc.level])
    if m.hasNote(loc):
      l.delAnnotation(loc.row, loc.col)

# }}}
# {{{ setLabel*()
proc setLabel*(map; loc: Location, n: Annotation; um) =

  singleCellAction(map, loc, um, "Set label", m):
    if not m.isEmpty(loc):
      m.setFloor(loc, fBlank)

    alias(l, m.levels[loc.level])
    l.setAnnotation(loc.row, loc.col, n)

# }}}
# {{{ eraseLabel*()
proc eraseLabel*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Erase label", m):
    alias(l, m.levels[loc.level])
    if m.hasLabel(loc):
      l.delAnnotation(loc.row, loc.col)

# }}}
# {{{ setLink*()
proc setLink*(map; src, dest: Location, floorColor: byte; um) =
  let srcFloor = map.getFloor(src)
  let linkType = linkFloorToString(srcFloor)

  let usd = UndoStateData(
    actionName: fmt"Set link destination {EnDash} {linkType}",
    location: Location(level: src.level, row: src.row, col: src.col)
  )

  # Do Action
  let action = proc (m: var Map): UndoStateData =
    # edge case: support for overwriting existing link
    # (delete existing links originating from src)
    m.links.delBySrc(src)
    m.links.delByDest(src)

    var destFloor: Floor
    if   srcFloor in LinkPitSources:       destFloor = fCeilingPit
    elif srcFloor == fTeleportSource:      destFloor = fTeleportDestination
    elif srcFloor == fTeleportDestination: destFloor = fTeleportSource
    elif srcFloor == fEntranceDoor:        destFloor = fExitDoor
    elif srcFloor == fExitDoor:            destFloor = fEntranceDoor
    elif srcFloor in LinkStairs:
      let
        srcElevation = m.levels[src.level].elevation
        destElevation = m.levels[dest.level].elevation

      if srcElevation < destElevation:
        destFloor = fStairsDown
        m.setFloor(src, fStairsUp)

      elif srcElevation > destElevation:
        destFloor = fStairsUp
        m.setFloor(src, fStairsDown)

      else:
        destFloor = if srcFloor == fStairsUp: fStairsDown else: fStairsUp

    m.setFloor(dest, destFloor)

    m.links.set(src, dest)
    m.levels[dest.level].reindexNotes()
    result = usd

  # Undo Action
  let
    r = dest.row
    c = dest.col
    rect = rectN(r, c, r+1, c+1)  # single cell

  let undoLevel = newLevelFrom(map.levels[dest.level], rect)

  var oldLinks = initLinks()

  var old = map.links.getBySrc(dest)
  if old.isSome: oldLinks.set(dest, old.get)

  old = map.links.getByDest(dest)
  if old.isSome: oldLinks.set(old.get, dest)

  old = map.links.getBySrc(src)
  if old.isSome: oldLinks.set(src, old.get)

  old = map.links.getByDest(src)
  if old.isSome: oldLinks.set(old.get, src)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[dest.level].copyCellsAndAnnotationsFrom(
      destRow = rect.r1,
      destCol = rect.c1,
      src     = undoLevel,
      srcRect = rectN(0, 0, 1, 1)  # single cell
    )
    m.levels[dest.level].reindexNotes()

    # Delete existing links in undo area
    m.links.delBySrc(dest)
    m.links.delByDest(dest)

    m.links.addAll(oldLinks)

    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# {{{ eraseSelection*()
proc eraseSelection*(map; level: Natural, sel: Selection,
                     bbox: Rect[Natural]; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false,
                 "Erase selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc)

# }}}
# {{{ fillSelection*()
proc fillSelection*(map; level: Natural, sel: Selection,
                    bbox: Rect[Natural], floorColor: byte; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false,
                 "Fill selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc)
          m.setFloor(loc, fBlank)
          m.setFloorColor(loc, floorColor)

# }}}
# {{{ surroundSelection*()
proc surroundSelectionWithWalls*(map; level: Natural, sel: Selection,
                                 bbox: Rect[Natural]; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false,
                 "Surround selection with walls", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c

          proc setWall(m: var Map, dir: CardinalDir) =
            if m.canSetWall(loc, dir):
              m.setWall(loc, dir, wWall)

          if sel.isNeighbourCellEmpty(r,c, dirN): setWall(m, dirN)
          if sel.isNeighbourCellEmpty(r,c, dirE): setWall(m, dirE)
          if sel.isNeighbourCellEmpty(r,c, dirS): setWall(m, dirS)
          if sel.isNeighbourCellEmpty(r,c, dirW): setWall(m, dirW)

# }}}
# {{{ setSelectionFloorColor*()
proc setSelectionFloorColor*(map; level: Natural, sel: Selection,
                             bbox: Rect[Natural], floorColor: byte; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, bbox, um, groupWithPrev=false,
                 "Set floor color of selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          if not m.isEmpty(loc):
            m.setFloorColor(loc, floorColor)

# }}}
# {{{ cutSelection*()
proc cutSelection*(map; loc: Location, bbox: Rect[Natural], sel: Selection,
                   linkDestLevelIndex: Natural; um) =

  let level = loc.level
  var oldLinks = map.links.filterByInRect(level, bbox, sel.some)

  proc transformAndCollectLinks(origLinks: Links, linksBuf: var Links,
                                selection: Selection, bbox: Rect[Natural]) =
    for src, dest in origLinks.pairs:
      var src = src
      var dest = dest
      var addLink = false

      # Transform location so it's relative to the top-left corner of the
      # buffer
      if src.level == level and
         bbox.contains(src.row, src.col) and selection[src.row, src.col]:
        src.level = linkDestLevelIndex
        src.row = src.row - bbox.r1
        src.col = src.col - bbox.c1
        addLink = true

      if dest.level == level and
         bbox.contains(dest.row, dest.col) and selection[dest.row, dest.col]:

        dest.level = linkDestLevelIndex
        dest.row = dest.row - bbox.r1
        dest.col = dest.col - bbox.c1
        addLink = true

      if addLink:
        linksBuf.set(src, dest)


  var newLinks = initLinks()
  transformAndCollectLinks(oldLinks, newLinks, sel, bbox)


  cellAreaAction(map, loc, bbox, um, groupWithPrev=false, "Cut selection", m):

    for s in oldLinks.keys: m.links.delBySrc(s)
    m.links.addAll(newLinks)

    var l: Location
    l.level = level

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          l.row = r
          l.col = c
          m.eraseCell(l)

# }}}
# {{{ pasteSelection*()
proc pasteSelection*(map; pasteLoc: Location, sb: SelectionBuffer,
                     linkSrcLevelIndex: Natural; um;
                     groupWithPrev: bool = false,
                     pasteTrail: bool = false,
                     actionName: string = "Pasted buffer") =

  let rect = rectN(
    pasteLoc.row,
    pasteLoc.col,
    pasteLoc.row + sb.level.rows,
    pasteLoc.col + sb.level.cols
  ).intersect(
    rectN(
      0,
      0,
      map.levels[pasteLoc.level].rows,
      map.levels[pasteLoc.level].cols)
  )

  if rect.isSome:
    cellAreaAction(map, pasteLoc, rect.get, um, groupWithPrev, actionName, m):

      alias(l, m.levels[pasteLoc.level])

      let bbox = l.paste(pasteLoc.row, pasteLoc.col, sb.level, sb.selection,
                         pasteTrail)

      if bbox.isSome:
        let bbox = bbox.get
        var loc = Location(level: pasteLoc.level)

        # Erase links in the paste area
        for r in bbox.r1..<bbox.r2:
          for c in bbox.c1..<bbox.c2:
            loc.row = r
            loc.col = c
            m.eraseCellLinks(loc)


        # Recreate links from the copy buffer
        var linkKeysToRemove = newSeq[Location]()
        var linksToAdd = initLinks()

        for src, dest in m.links.pairs:
          var
            src = src
            dest = dest
            addLink = false
            srcInside = true
            destInside = true

          if src.level == linkSrcLevelIndex:
            linkKeysToRemove.add(src)
            src.level = pasteLoc.level
            src.row += pasteLoc.row
            src.col += pasteLoc.col
            srcInside = bbox.contains(src.row, src.col)
            addLink = true

          if dest.level == linkSrcLevelIndex:
            linkKeysToRemove.add(src)
            dest.level = pasteLoc.level
            dest.row += pasteLoc.row
            dest.col += pasteLoc.col
            destInside = bbox.contains(dest.row, dest.col)
            addLink = true

          if addLink and srcInside and destInside:
            linksToAdd[src] = dest

        for s in linkKeysToRemove: m.links.delByKey(s)
        m.links.addAll(linksToAdd)

        m.normaliseLinkedStairs(pasteLoc.level)

# }}}

# {{{ addNewLevel*()
proc addNewLevel*(map; loc: Location, locationName, levelName: string,
                  elevation: int, rows, cols: Natural,
                  overrideCoordOpts: bool, coordOpts: CoordinateOptions,
                  regionOpts: RegionOptions; um): Location =

  let usd = UndoStateData(actionName: "New level", location: loc)

  let action = proc (m: var Map): UndoStateData =
    let newLevel = newLevel(locationName, levelName, elevation, rows, cols,
                            overrideCoordOpts, coordOpts, regionOpts)
    m.addLevel(newLevel)

    var usd = usd
    usd.location.level = m.levels.high
    result = usd


  let undoAction = proc (m: var Map): UndoStateData =
    let level = m.levels.high
    m.delLevel(level)

    for src in m.links.filterByLevel(level).keys:
      m.links.delBySrc(src)

    result = usd

  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ deleteLevel*()
proc deleteLevel*(map; loc: Location; um): Location =

  let usd = UndoStateData(actionName: "Delete level", location: loc)

  let oldLinks = map.links.filterByLevel(loc.level)

  let action = proc (m: var Map): UndoStateData =
    let adjustLinks = loc.level < m.levels.high

    let currSortedLevelIdx = m.findSortedLevelIdxByLevelIdx(usd.location.level)

    # if the deleted level wasn't the last, moves the last level into
    # the "hole" created by the delete
    m.delLevel(loc.level)

    for src in oldLinks.keys:
      m.links.delBySrc(src)

    if adjustLinks:
      let oldLevelIdx = m.levels.high+1
      let newLevelIdx = loc.level
      m.links.remapLevelIndex(oldLevelIdx, newLevelIdx)

    var usd = usd
    if m.levels.len == 0:
      usd.location.level = 0
    else:
      usd.location.level = m.sortedLevelIdxToLevelIdx[
        min(currSortedLevelIdx, m.levels.high)
      ]

    result = usd


  let undoLevel = newLevelFrom(map.levels[loc.level])

  let undoAction = proc (m: var Map): UndoStateData =
    let restoredLevel = newLevelFrom(undoLevel)

    if loc.level > m.levels.high:
      m.levels.add(restoredLevel)
    else:
      # move to the end
      let lastLevel = m.levels[loc.level]
      m.levels.add(lastLevel)

      m.levels[loc.level] = restoredLevel
      m.links.remapLevelIndex(oldIndex = loc.level, newIndex = m.levels.high)

    m.refreshSortedLevelNames()
    m.links.addAll(oldLinks)

    result = usd

  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ resizeLevel*()
proc resizeLevel*(map; loc: Location, newRows, newCols: Natural,
                  align: Direction; um): Location =

  let usd = UndoStateData(actionName: "Resize level", location: loc)

  let
    oldLinks = map.links.filterByLevel(loc.level)

    (destRow, destCol, copyRect) =
      map.levels[loc.level].calcResizeParams(newRows, newCols, align)

    newLevelRect = rectI(0, 0, newRows, newCols)
    rowOffs = destRow.int - copyRect.r1
    colOffs = destCol.int - copyRect.c1

    newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                          newLevelRect)

  let action = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])

    # TODO region names needs to be updated when resizing the level
    # (search for newRegionNames and update all occurences)
    let newRegionNames = l.regionNames

    var newLevel = newLevel(l.locationName, l.levelName, l.elevation,
                            newRows, newCols, l.overrideCoordOpts, l.coordOpts,
                            l.regionOpts, newRegionNames)

    newLevel.copyCellsAndAnnotationsFrom(destRow, destCol, l, copyRect)
    l = newLevel

    for src in oldLinks.keys: m.links.delBySrc(src)
    m.links.addAll(newLinks)

    var usd = usd
    let loc = usd.location
    usd.location.col = (loc.col.int + colOffs).clamp(0, newCols-1).Natural
    usd.location.row = (loc.row.int + rowOffs).clamp(0, newRows-1).Natural
    result = usd


  let undoLevel = newLevelFrom(map.levels[loc.level])

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = newLevelFrom(undoLevel)

    for src in newLinks.keys: m.links.delBySrc(src)
    m.links.addAll(oldLinks)
    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ cropLevel*()
proc cropLevel*(map; loc: Location, cropRect: Rect[Natural]; um): Location =

  let usd = UndoStateData(actionName: "Crop level", location: loc)

  let
    oldLinks = map.links.filterByLevel(loc.level)

    newLevelRect = rectI(0, 0, cropRect.rows, cropRect.cols)
    rowOffs = -cropRect.r1
    colOffs = -cropRect.c1

    newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                          newLevelRect)


  let action = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = newLevelFrom(m.levels[loc.level], cropRect)

    for src in oldLinks.keys: m.links.delBySrc(src)
    m.links.addAll(newLinks)

    var usd = usd
    usd.location.col = (usd.location.col.int + colOffs).Natural
    usd.location.row = (usd.location.row.int + rowOffs).Natural
    result = usd


  let undoLevel = newLevelFrom(map.levels[loc.level])

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = newLevelFrom(undoLevel)

    for src in newLinks.keys: m.links.delBySrc(src)
    m.links.addAll(oldLinks)
    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ nudgeLevel*()
proc nudgeLevel*(map; loc: Location, rowOffs, colOffs: int,
                 sb: SelectionBuffer; um): Location =

  let usd = UndoStateData(actionName: "Nudge level", location: loc)

  let levelRect = rectI(0, 0, sb.level.rows, sb.level.cols)

  let oldLinks = map.links.filterByLevel(loc.level)
  let newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                            levelRect)

  # The level is cleared for the duration of the nudge operation and it is
  # stored temporarily in the SelectionBuffer
  let action = proc (m: var Map): UndoStateData =
    var l = newLevel(
      sb.level.locationName,
      sb.level.levelName,
      sb.level.elevation,
      sb.level.rows,
      sb.level.cols,
      sb.level.overrideCoordOpts,
      sb.level.coordOpts,
      sb.level.regionOpts,
      sb.level.regionNames
    )
    discard l.paste(rowOffs, colOffs, sb.level, sb.selection, pasteTrail=true)
    m.levels[loc.level] = l

    for src in oldLinks.keys: m.links.delBySrc(src)
    m.links.addAll(newLinks)

    var usd = usd
    usd.location.row = max(usd.location.row + rowOffs, 0)
    usd.location.col = max(usd.location.col + colOffs, 0)
    result = usd


  let undoLevel = newLevelFrom(sb.level)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = newLevelFrom(undoLevel)

    for src in newLinks.keys: m.links.delBySrc(src)
    m.links.addAll(oldLinks)

    result = usd

  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ setLevelProps*()
proc setLevelProps*(map; loc: Location, locationName, levelName: string,
                    elevation: int, overrideCoordOpts: bool,
                    coordOpts: CoordinateOptions, regionOpts: RegionOptions;
                    um) =

  let usd = UndoStateData(actionName: "Edit level properties", location: loc)

  let action = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])

    let prevElevation = l.elevation

    l.locationName = locationName
    l.levelName = levelName
    l.elevation = elevation
    l.overrideCoordOpts = overrideCoordOpts
    l.coordOpts = coordOpts
    l.regionOpts = regionOpts

    if prevElevation != elevation:
      m.normaliseLinkedStairs(loc.level)

    m.refreshSortedLevelNames()
    result = usd

  alias(l, map.levels[loc.level])
  let
    oldLocationName = l.locationName
    oldLevelName = l.levelName
    oldElevation = l.elevation
    oldOverrideCoordOpts = l.overrideCoordOpts
    oldCoordOpts = l.coordOpts
    oldRegionOpts = l.regionOpts

  var undoAction = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])

    let prevElevation = l.elevation

    l.locationName = oldLocationName
    l.levelName = oldLevelName
    l.elevation = oldElevation
    l.overrideCoordOpts = oldOverrideCoordOpts
    l.coordOpts = oldCoordOpts
    l.regionOpts = oldRegionOpts

    if prevElevation != oldElevation:
      m.normaliseLinkedStairs(loc.level)

    m.refreshSortedLevelNames()
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ setMapProps*()
proc setMapProps*(map; loc: Location, name: string,
                  coordOpts: CoordinateOptions; um) =

  let usd = UndoStateData(actionName: "Edit map properties", location: loc)

  let action = proc (m: var Map): UndoStateData =
    m.name = name
    m.coordOpts = coordOpts
    result = usd

  let
    oldName = map.name
    oldCoordOpts = map.coordOpts

  var undoAction = proc (m: var Map): UndoStateData =
    m.name = oldName
    m.coordOpts = oldCoordOpts
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
