import algorithm
import math
import logging except Level
import options
import strformat
import strutils
import sugar
import unicode

import riff

import bitable
import common
import drawlevel
import fieldlimits
import icons
import level
import map
import utils
import theme


# TODO use app version instead?
const CurrentMapVersion = 1

# {{{ Field limits

const
  MapNameLimits*           = strLimits(minLen=1, maxLen=400, maxRuneLen=100)

  NumLevelsLimits*         = intLimits(min=0, max=999)
  LevelLocationNameLimits* = strLimits(minLen=1, maxLen=400, maxRuneLen=100)
  LevelNameLimits*         = strLimits(minLen=0, maxLen=400, maxRuneLen=100)
  LevelElevationLimits*    = intLimits(min= -200, max=200)
  LevelRowsLimits*         = intLimits(min=1, max=6666)
  LevelColumnsLimits*      = intLimits(min=1, max=6666)

  RegionNameLimits*        = strLimits(minLen=0, maxLen=400, maxRuneLen=100)
  RegionRowsLimits*        = intLimits(min=2, max=6666)
  RegionColumnsLimits*     = intLimits(min=2, max=6666)

  CellFloorColorLimits*    = intLimits(min=0, max=LevelStyle.floorColor.len)

  NumAnnotationsLimits*    = intLimits(min=0, max=10_000)
  NoteTextLimits*          = strLimits(minLen=1, maxLen=1600, maxRuneLen=400)
  NoteCustomIdLimits*      = strLimits(minLen=1, maxLen=2, maxRuneLen=2)
  NoteColorLimits*         = intLimits(min=0, max=LevelStyle.noteIndexBgColor.len)
  NoteIconLimits*          = intLimits(min=0, max=NoteIconMax)

  NumLinksLimits*          = intLimits(min=0, max=10_000)

  ThemeNameLimits*         = strLimits(minLen=1, maxLen=200, maxRuneLen=200)

  ZoomLevelLimits*         = intLimits(min=MinZoomLevel, max=MaxZoomLevel)

# }}}

const
  FourCC_GRDM      = "GRMM"
  FourCC_GRDM_cell = "cell"
  FourCC_GRDM_coor = "coor"
  FourCC_GRDM_disp = "disp"
  FourCC_GRDM_lnks = "lnks"
  FourCC_GRDM_lvl  = "lvl "
  FourCC_GRDM_lvls = "lvls"
  FourCC_GRDM_map  = "map "
  FourCC_GRDM_anno = "anno"
  FourCC_GRDM_prop = "prop"
  FourCC_GRDM_regn = "regn"


type MapReadError* = object of IOError

proc raiseMapReadError(s: string) =
  raise newException(MapReadError, s)


type
  MapDisplayOptions* = object
    currLevel*:       Natural
    zoomLevel*:       Natural
    cursorRow*:       Natural
    cursorCol*:       Natural
    viewStartRow*:    Natural
    viewStartCol*:    Natural


# {{{ Read
# TODO move utils into nim-riff?
# {{{ appendInGroupChunkMsg()
proc appendInGroupChunkMsg(msg: string, groupChunkId: Option[string]): string =
  if groupChunkId.isSome:
    msg & fmt" inside a '{groupChunkId.get}' group chunk"
  else: msg

# }}}

# {{{ chunkOnlyOnceError()
proc chunkOnlyOnceError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"'{chunkId}' chunk can only appear once"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

# }}}
# {{{ chunkNotFoundError()
proc chunkNotFoundError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"Mandatory '{chunkId}' chunk not found"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

# }}}
# {{{ invalidChunkError()
proc invalidChunkError(chunkId, groupChunkId: string) =
  var msg = fmt"'{chunkId}' chunk is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)

# }}}
# {{{ invalidListChunkError()
proc invalidListChunkError(formatTypeId, groupChunkId: string) =
  var msg = fmt"'LIST' chunk with format type '{formatTypeId}' is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)

# }}}

# {{{ checkStringLength()
proc checkStringLength(s: string, name: string, limit: FieldLimits) =
  if s.len < limit.minLen or s.len > limit.maxLen:
    raiseMapReadError(
      fmt"The length of {name} must be between {limit.minLen} and " &
      fmt"{limit.maxLen} bytes, actual length: {s.len}, value: {s}"
    )

  if s.runeLen > limit.maxRuneLen:
    raiseMapReadError(
      fmt"The maximum allowed length of {name} is {limit.maxRuneLen} " &
      fmt"UTF-8 code points, actual length: {s.runeLen}, value: {s}"
    )

# }}}
# {{{ checkValueRange()
proc checkValueRange[T: SomeInteger](v: T, name: string,
                                     min: T = 0, max: T = 0) =
  if v < min or v > max:
    raiseMapReadError(
      fmt"The value of {name} must be between {min} and " &
      fmt"{max}, actual value: {v}"
    )

proc checkValueRange[T: SomeInteger](v: T, name: string, limit: FieldLimits) =
  checkValueRange(v, name, T(limit.minInt), T(limit.maxInt))

# }}}
# {{{ checkEnum()
proc checkEnum(v: SomeInteger, name: string, E: typedesc[enum]) =
  var valid: bool
  try:
    let ev = $E(v)
    valid = not ev.contains("invalid data")
  except RangeDefect:
    valid = false

  if not valid:
    raiseMapReadError(fmt"Invalid enum value for {name}: {v}")

# }}}

using rr: RiffReader

# {{{ readLocation()
proc readLocation(rr): Location =
  result.level = rr.read(uint16).int
  result.row = rr.read(uint16)
  result.col = rr.read(uint16)

# }}}
# {{{ readDisplayOptions_v1()
proc readDisplayOptions_v1(rr): MapDisplayOptions =
  info(fmt"Reading display options...")

  # TODO
  discard


# }}}
# {{{ readLinks_v1()
proc readLinks_v1(rr; levels: seq[Level]): BiTable[Location, Location] =
  info(fmt"Reading links...")

  var numLinks = rr.read(uint16).int
  checkValueRange(numLinks, "links.numLinks", NumLinksLimits)

  result = initBiTable[Location, Location](nextPowerOfTwo(numLinks))

  let maxLevelIndex = NumLevelsLimits.maxInt - 1

  while numLinks > 0:
    let src = readLocation(rr)
    checkValueRange(src.level, "lnks.srcLevel", max=maxLevelIndex)
    checkValueRange(src.row, "lnks.srcRow", max=levels[src.level].rows-1)
    checkValueRange(src.col, "lnks.srcColumh", max=levels[src.level].cols-1)

    let dest = readLocation(rr)
    checkValueRange(dest.level, "lnks.destLevel", max=maxLevelIndex)
    checkValueRange(dest.row, "lnks.destRow", max=levels[dest.level].cols-1)
    checkValueRange(dest.col, "lnks.destColumh", max=levels[dest.level].cols-1)

    result[src] = dest
    dec(numLinks)

# }}}
# {{{ readLevelProperties_v1()
proc readLevelProperties_v1(rr): Level =
  info(fmt"Reading level properties...")

  let locationName = rr.readWStr()
  info(fmt"  locationName: {locationName}")
  checkStringLength(locationName, "lvl.prop.locationName",
                    LevelLocationNameLimits)

  let levelName = rr.readWStr()
  info(fmt"  levelName: {levelName}")
  checkStringLength(levelName, "lvl.prop.levelName", LevelNameLimits)

  let elevation = rr.read(int16).int
  info(fmt"  elevation: {elevation}")
  checkValueRange(elevation, "lvl.prop.elevation", LevelElevationLimits)

  let numRows = rr.read(uint16)
  info(fmt"  numRows: {numRows}")
  checkValueRange(numRows, "lvl.prop.numRows", LevelRowsLimits)

  let numColumns = rr.read(uint16)
  info(fmt"  numColumns: {numColumns}")
  checkValueRange(numColumns, "lvl.prop.numColumns", LevelColumnsLimits)

  let overrideCoordOpts = rr.read(uint8).bool
  info(fmt"  overrideCoordOpts: {overrideCoordOpts}")

  result = newLevel(locationName, levelName, elevation, numRows, numColumns)
  result.overrideCoordOpts = overrideCoordOpts

# }}}
# {{{ readLevelData_v1()
proc readLevelData_v1(rr; numCells: Natural): seq[Cell] =
  info(fmt"Reading level data...")

  var cells: seq[Cell]
  newSeq[Cell](cells, numCells)

  for i in 0..<numCells:
    let floor = rr.read(uint8)
    checkEnum(floor, "lvl.cell.floor", Floor)

    let floorOrientation = rr.read(uint8)
    checkEnum(floorOrientation, "lvl.cell.floorOrientation", Orientation)

    let floorColor = rr.read(uint8)
    checkValueRange(floorColor, "lvl.cell.floorColor", CellFloorColorLimits)

    let wallN = rr.read(uint8)
    checkEnum(wallN, "lvl.cell.wallN", Wall)

    let wallW = rr.read(uint8)
    checkEnum(wallW, "lvl.cell.wallW", Wall)

    let trail = rr.read(uint8).bool

    cells[i] = Cell(
      floor: floor.Floor,
      floorOrientation: floorOrientation.Orientation,
      floorColor: floorColor,
      wallN: wallN.Wall,
      wallW: wallW.Wall,
      trail: trail
    )

  result = cells

# }}}
# {{{ readLevelAnnotations_v1()
proc readLevelAnnotations_v1(rr; l: Level) =
  info(fmt"Reading annotations...")

  let numAnnotations = rr.read(uint16).Natural
  info(fmt"  numAnnotations: {numAnnotations}")
  checkValueRange(numAnnotations, "lvl.anno.numAnnotations",
                  NumAnnotationsLimits)

  for i in 0..<numAnnotations:
    debug(fmt"  annotation index: {i}")

    let row = rr.read(uint16)
    debug(fmt"  row: {row}")
    checkValueRange(row, "lvl.anno.row", max=l.rows.uint16-1)

    let col = rr.read(uint16)
    debug(fmt"  col: {col}")
    checkValueRange(col, "lvl.anno.col", max=l.cols.uint16-1)

    let kind = rr.read(uint8)
    debug(fmt"  kind: {kind}")
    checkEnum(kind, "lvl.anno.kind", AnnotationKind)

    var anno = Annotation(kind: AnnotationKind(kind))

    case anno.kind
    of akComment:
      discard

    of akIndexed:
      let index = rr.read(uint16)
      debug(fmt"    index: {index}")
      checkValueRange(index, "lvl.anno.index",
                      max=NumAnnotationsLimits.maxInt-1)
      anno.index = index

      let indexColor = rr.read(uint8)
      debug(fmt"    indexColor: {indexColor}")
      checkValueRange(indexColor, "lvl.anno.indexColor", NoteColorLimits)
      anno.indexColor = indexColor

    of akIcon:
      let icon = rr.read(uint8)
      debug(fmt"    icon: {icon}")
      checkValueRange(icon, "lvl.anno.icon", NoteIconLimits)
      anno.icon = icon

    of akCustomId:
      let customId = rr.readBStr()
      debug(fmt"    customId: {customId}")
      checkStringLength(customId, "lvl.anno.customId", NoteCustomIdLimits)
      anno.customId = customId

    of akLabel:
      let labelColor = rr.read(uint8)
      debug(fmt"    labelColor: {labelColor}")
      checkValueRange(labelColor, "lvl.anno.labelColor", NoteColorLimits)
      anno.labelColor = labelColor
#      discard

    let text = rr.readWStr()
    debug(fmt"    text: {text}")

    checkStringLength(text, "lvl.anno.text", NoteTextLimits)

    anno.text = text
    l.setAnnotation(row, col, anno)

# }}}
# {{{ readCoordinateOptions_v1*()
proc readCoordinateOptions_v1(rr; parentChunk: string): CoordinateOptions =
  info(fmt"Reading coordinate options...")

  let origin = rr.read(uint8)
  checkEnum(origin, fmt"${parentChunk}.coor.origin", CoordinateOrigin)

  let rowStyle = rr.read(uint8)
  checkEnum(rowStyle, fmt"${parentChunk}.coor.rowStyle", CoordinateStyle)

  let columnStyle = rr.read(uint8)
  checkEnum(columnStyle, fmt"${parentChunk}.coor.columnStyle", CoordinateStyle)

  let rowStart = rr.read(int16)
  let columnStart = rr.read(int16)

  result = CoordinateOptions(
    origin:      origin.CoordinateOrigin,
    rowStyle:    rowStyle.CoordinateStyle,
    columnStyle: columnStyle.CoordinateStyle,
    rowStart:    rowStart,
    columnStart: columnStart
  )

# }}}
# {{{ readRegions_v1*()
proc readRegions_v1(rr): (RegionOptions, seq[string]) =
  info(fmt"Reading regions...")

  let enableRegions = rr.read(uint8).bool

  let regionColumns = rr.read(uint16)
  checkValueRange(regionColumns, "lvl.regn.regionColumns", RegionColumnsLimits)

  let regionRows = rr.read(uint16)
  checkValueRange(regionRows, "lvl.regn.regionRows", RegionRowsLimits)

  let perRegionCoords = rr.read(uint8).bool

  let regionOpts = RegionOptions(
    enableRegions:   enableRegions,
    regionColumns:   regionColumns,
    regionRows:      regionRows,
    perRegionCoords: perRegionCoords
  )

  let numRegions = rr.read(uint16).Natural

  var regionNames: seq[string] = @[]
  for i in 0..<numRegions:
    let name = rr.readBStr()
    checkStringLength(name, "lvl.regn.regionName", RegionNameLimits)
    regionNames.add(name)

  result = (regionOpts, regionNames)

# }}}
# {{{ readLevel_v1()
proc readLevel_v1(rr): Level =
  info(fmt"Reading level...")

  let groupChunkId = FourCC_GRDM_lvls.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none
    regnCursor = Cursor.none
    cellCursor = Cursor.none
    annoCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRDM_lvl}' group chunk is empty")

  var ci = rr.enterGroup()

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      of FourCC_GRDM_regn:
        if regnCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_regn, groupChunkId)
        regnCursor = rr.cursor.some

      of FourCC_GRDM_cell:
        if cellCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_cell, groupChunkId)
        cellCursor = rr.cursor.some

      of FourCC_GRDM_anno:
        if annoCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_anno, groupChunkId)
        annoCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRDM_coor)
  if regnCursor.isNone: chunkNotFoundError(FourCC_GRDM_regn)
  if cellCursor.isNone: chunkNotFoundError(FourCC_GRDM_cell)

  rr.cursor = propCursor.get
  var level = readLevelProperties_v1(rr)

  rr.cursor = coorCursor.get
  level.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  rr.cursor = regnCursor.get
  (level.regionOpts, level.regionNames) = readRegions_v1(rr)

  rr.cursor = cellCursor.get

  # +1 needed because of the south & east borders
  let numCells = (level.rows+1) * (level.cols+1)

  level.cellGrid.cells = readLevelData_v1(rr, numCells)

  if annoCursor.isSome:
    rr.cursor = annoCursor.get
    readLevelAnnotations_v1(rr, level)

  result = level

# }}}
# {{{ readLevelList_v1()
proc readLevelList_v1(rr): seq[Level] =
  info(fmt"Reading level list...")

  var levels = newSeq[Level]()

  if rr.hasSubChunks():
    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRDM_lvl:
          if levels.len > NumLevelsLimits.maxInt:
            raiseMapReadError(
              fmt"Map cannot contain more than {NumLevelsLimits.maxInt} levels"
            )

          levels.add(readLevel_v1(rr))
          rr.exitGroup()
        else:
          invalidListChunkError(ci.formatTypeId, FourCC_GRDM_lvls)

      else: # not group chunk
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

  result = levels

# }}}
# {{{ readMapProperties_v1()
proc readMapProperties_v1(rr): Map =
  info(fmt"Reading map properties...")

  # TODO is inside Map the best place for this? or introduce a header chunk?
  let version = rr.read(uint16)
  info(fmt"  version: {version}")
  if version > CurrentMapVersion:
    raiseMapReadError(fmt"Unsupported map file version: {version}")

  let name = rr.readBStr()
  info(fmt"  name: {name}")
  checkStringLength(name, "map.prop.name", MapNameLimits)

  result = newMap(name)

# }}}
# {{{ readMap_v1()
proc readMap_v1(rr): Map =
  info(fmt"Reading GRDM.map chunk...")

  let groupChunkId = FourCC_GRDM_map.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRDM_map}' group chunk is empty")

  var ci = rr.enterGroup()

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRDM_coor)

  rr.cursor = propCursor.get
  var map = readMapProperties_v1(rr)

  rr.cursor = coorCursor.get
  map.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  result = map

# }}}
# # {{{ readMapFile*()
# TODO return display related info and info chunk data as well
proc readMapFile*(filename: string): Map =
  var rr: RiffReader
  try:
    rr = openRiffFile(filename)

    let riffChunk = rr.currentChunk
    if riffChunk.formatTypeId != FourCC_GRDM:
      raiseMapReadError(
        fmt"Not a Gridmonger map file, " &
        fmt"RIFF formatTypeId: {fourCCToCharStr(riffChunk.formatTypeId)}"
      )

    info(fmt"Map headers OK")

    var
      mapCursor = Cursor.none
      linksCursor = Cursor.none
      levelListCursor = Cursor.none
      displayOptsCursor = Cursor.none

    # Find chunks
    if not rr.hasSubchunks():
      raiseMapReadError("RIFF chunk contains no subchunks")

    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_INFO:
          info(fmt"INFO chunk found")
          discard  # TODO

        of FourCC_GRDM_map:
          info(fmt"GRDM.map group chunk found")
          if mapCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_map)
          mapCursor = rr.cursor.some

        of FourCC_GRDM_lvls:
          info(fmt"GRDM.lvls group chunk found")
          if levelListCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lvls)
          levelListCursor = rr.cursor.some

        else: discard   # skip unknown top level group chunks

      elif ci.kind == ckChunk:
        case ci.id

        of FourCC_GRDM_lnks:
          info(fmt"GRDM.lnks chunk found")
          if linksCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lnks)
          linksCursor = rr.cursor.some

        of FourCC_GRDM_disp:
          info(fmt"GRDM.lnks disp found")
          if displayOptsCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_disp)
          displayOptsCursor = rr.cursor.some

        else:
          info(fmt"Skiping unknown top level chunk, " &
               fmt"chunkId: {fourCCToCharStr(ci.id)}")

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

    # Check for mandatory chunks
    if mapCursor.isNone:       chunkNotFoundError(FourCC_GRDM_map)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRDM_lnks)

    # Load chunks
    rr.cursor = mapCursor.get
    let m = readMap_v1(rr)

    rr.cursor = levelListCursor.get
    m.levels = readLevelList_v1(rr)
    m.refreshSortedLevelNames()

    rr.cursor = linksCursor.get
    m.links = readLinks_v1(rr, m.levels)

    if displayOptsCursor.isSome:
      rr.cursor = displayOptsCursor.get
      discard readDisplayOptions_v1(rr)

    result = m

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error reading map file: {e.msg}", e)
  finally:
    if rr != nil: rr.close()

# }}}
# }}}

# {{{ Write

using rw: RiffWriter

# {{{ writeDisplayOptions_v1()
proc writeDisplayOptions_v1(rw; opts: MapDisplayOptions) =
  rw.beginChunk(FourCC_GRDM_disp)

  rw.write(opts.currLevel.uint16)
  rw.write(opts.zoomLevel.uint8)
  rw.write(opts.cursorRow.uint16)
  rw.write(opts.cursorCol.uint16)
  rw.write(opts.viewStartRow.uint16)
  rw.write(opts.viewStartCol.uint16)

  rw.endChunk()

# }}}
# {{{ writeLinks_v1()
proc writeLinks_v1(rw; links: BiTable[Location, Location]) =
  rw.beginChunk(FourCC_GRDM_lnks)
  rw.write(links.len.uint16)

  var sortedKeys = collect(newSeqOfCap(links.len)):
    for k in links.keys(): k

  sort(sortedKeys)

  proc writeLocation(loc: Location) =
    rw.write(loc.level.uint16)
    rw.write(loc.row.uint16)
    rw.write(loc.col.uint16)

  for src in sortedKeys:
    let dest = links[src].get
    writeLocation(src)
    writeLocation(dest)

  rw.endChunk()

# }}}
# {{{ writeCoordinateOptions_v1()
proc writeCoordinateOptions_v1(rw; co: CoordinateOptions) =
  rw.beginChunk(FourCC_GRDM_coor)

  rw.write(co.origin.uint8)
  rw.write(co.rowStyle.uint8)
  rw.write(co.columnStyle.uint8)
  rw.write(co.rowStart.int16)
  rw.write(co.columnStart.int16)

  rw.endChunk()

# }}}
# {{{ writeRegions_v1()
proc writeRegions_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_regn)

  rw.write(l.regionOpts.enableRegions.uint8)
  rw.write(l.regionOpts.regionColumns.uint16)
  rw.write(l.regionOpts.regionRows.uint16)
  rw.write(l.regionOpts.perRegionCoords.uint8)

  rw.write(l.regionNames.len.uint16)
  for name in l.regionNames:
    rw.writeBStr(name)

  rw.endChunk()

# }}}
# # {{{ writeLevelProperties_v1()
proc writeLevelProperties_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_prop)

  rw.writeWStr(l.locationName)
  rw.writeWStr(l.levelName)
  rw.write(l.elevation.int16)

  rw.write(l.rows.uint16)
  rw.write(l.cols.uint16)

  rw.write(l.overrideCoordOpts.uint8)

  rw.endChunk()

# }}}
# {{{ writeLevelCells_v1()
proc writeLevelCells_v1(rw; cells: seq[Cell]) =
  rw.beginChunk(FourCC_GRDM_cell)

  for c in cells:
    rw.write(c.floor.uint8)
    rw.write(c.floorOrientation.uint8)
    rw.write(c.floorColor.uint8)
    rw.write(c.wallN.uint8)
    rw.write(c.wallW.uint8)
    rw.write(c.trail.uint8)

  rw.endChunk()

# }}}
# {{{ writeLevelAnnotations_v1()
proc writeLevelAnnotations_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_anno)
#  rw.beginChunk("anno")

  rw.write(l.numAnnotations.uint16)

  for (row, col, anno) in l.allAnnotations:
    rw.write(row.uint16)
    rw.write(col.uint16)

    rw.write(anno.kind.uint8)
    case anno.kind
    of akComment: discard
    of akIndexed:
      rw.write(anno.index.uint16)
      rw.write(anno.indexColor.uint8)

    of akCustomId:
      rw.writeBStr(anno.customId)

    of akIcon:
      rw.write(anno.icon.uint8)

    of akLabel:
      rw.write(anno.labelColor.uint8)

    rw.writeWStr(anno.text)

  rw.endChunk()

# }}}
# {{{ writeLevel_v1()
proc writeLevel_v1(rw; l: Level) =
  rw.beginListChunk(FourCC_GRDM_lvl)

  writeLevelProperties_v1(rw, l)
  writeCoordinateOptions_v1(rw, l.coordOpts)
  writeRegions_v1(rw, l)
  writeLevelCells_v1(rw, l.cellGrid.cells)
  writeLevelAnnotations_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeLevelList_v1()
proc writeLevelList_v1(rw; levels: seq[Level]) =
  rw.beginListChunk(FourCC_GRDM_lvls)

  for l in levels:
    writeLevel_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeMapProperties_v1()
proc writeMapProperties_v1(rw; m: Map) =
  rw.beginChunk(FourCC_GRDM_prop)

  rw.write(CurrentMapVersion.uint16)
  rw.writeBStr(m.name)

  rw.endChunk()

# }}}
# {{{ writeMap_v1()
proc writeMap_v1(rw; m: Map) =
  rw.beginListChunk(FourCC_GRDM_map)

  writeMapProperties_v1(rw, m)
  writeCoordinateOptions_v1(rw, m.coordOpts)

  rw.endChunk()

# }}}
# {{{ writeMapFile*()
proc writeMapFile*(m: Map, opts: MapDisplayOptions, filename: string) =
  var rw: RiffWriter
  try:
    rw = createRiffFile(filename, FourCC_GRDM)

    writeMap_v1(rw, m)
    writeLevelList_v1(rw, m.levels)
    writeLinks_v1(rw, m.links)
    writeDisplayOptions_v1(rw, opts)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file: {e.msg}", e)
  finally:
    if rw != nil: rw.close()

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
