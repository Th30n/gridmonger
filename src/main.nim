import algorithm
import lenientops
import math
import options
import os
import strutils
import strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg

when not defined(DEBUG):
  import osdialog

import actions
import common
import csdwindow
import drawmap
import map
import persistence
import selection
import theme
import undomanager
import utils


const ThemesDir = "themes"

const DefaultZoomLevel = 5

const
  StatusBarHeight = 26.0

  MapLeftPad   = 50.0
  MapRightPad  = 120.0
  MapTopPadCoords      = 85.0
  MapBottomPadCoords   = 40.0
  MapTopPadNoCoords    = 65.0
  MapBottomPadNoCoords = 10.0

  NotesPaneTopPad = 10.0
  NotesPaneHeight = 40.0
  NotesPaneBottomPad = 10.0

# {{{ AppContext
type
  EditMode* = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearFloor,
    emSelectDraw,
    emSelectRect
    emPastePreview

  AppContext = ref object
    # Context
    win:            CSDWindow
    vg:             NVGContext

    # Dependencies
    undoManager:    UndoManager[Map]

    # Document (TODO group under 'doc'?)
    map:            Map

    # Options (TODO group under 'opts'?)
    scrollMargin:   Natural
    mapStyle:       MapStyle

    # UI state (TODO group under 'ui'?)
    editMode:       EditMode
    cursorCol:      Natural
    cursorRow:      Natural

    currSpecialWallIdx: Natural

    selection:      Option[Selection]
    selRect:        Option[SelectionRect]
    copyBuf:        Option[CopyBuffer]

    currMapLevel:   Natural
    statusIcon:     string
    statusMessage:  string
    statusCommands: seq[string]

    drawMapParams:     DrawMapParams
    toolbarDrawParams: DrawMapParams

    # Themes
    themeNames:     seq[string]
    currThemeIndex: Natural
    nextThemeIndex: Option[Natural]
    themeReloaded:  bool


    mapTopPad: float
    mapBottomPad: float

    showNotesPane: bool


var g_app: AppContext

using a: var AppContext

# }}}

# {{{ getPxRatio()
proc getPxRatio(a): float =
  let
    (winWidth, _) = a.win.size
    (fbWidth, _) = a.win.framebufferSize
  result = fbWidth / winWidth

# }}}

# {{{ Theme support
proc searchThemes(a) =
  for path in walkFiles(fmt"{ThemesDir}/*.cfg"):
    let (_, name, _) = splitFile(path)
    a.themeNames.add(name)
  sort(a.themeNames)

proc findThemeIndex(name: string, a): int =
  for i, n in a.themeNames:
    if n == name:
      return i
  return -1

proc loadTheme(index: Natural, a) =
  let name = a.themeNames[index]
  a.mapStyle = loadTheme(fmt"{ThemesDir}/{name}.cfg")
  a.currThemeIndex = index

# }}}

# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  a.statusIcon = ""
  a.statusMessage = ""
  a.statusCommands = @[]

# }}}
# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string], a) =
  a.statusIcon = icon
  a.statusMessage = msg
  a.statusCommands = commands

proc setStatusMessage(icon, msg: string, a) =
  setStatusMessage(icon , msg, commands = @[], a)

proc setStatusMessage(msg: string, a) =
  setStatusMessage(icon = "", msg, commands = @[], a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar(y: float, winWidth: float, a) =
  alias(vg, a.vg)
  alias(m, a.map)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(gray(0.2))
  vg.fill()

  # Display current coords
  vg.setFont(14.0)

  let cursorPos = fmt"({m.rows-1 - a.cursorRow}, {a.cursorCol})"
  let tw = vg.textWidth(cursorPos)

  vg.fillColor(gray(0.6))
  vg.textAlign(haLeft, vaMiddle)
  discard vg.text(winWidth - tw - 7, ty, cursorPos)

  vg.scissor(0, y, winWidth - tw - 15, StatusBarHeight)

  # Display icon & message
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 13
    CommandTextPadX = 10

  var x = 10.0

  vg.fillColor(gray(0.8))
  discard vg.text(IconPosX, ty, a.statusIcon)

  let tx = vg.text(MessagePosX, ty, a.statusMessage)
  x = tx + MessagePadX

  # Display commands, if present
  for i, cmd in a.statusCommands.pairs:
    if i mod 2 == 0:
      let label = cmd
      let w = vg.textWidth(label)

      vg.beginPath()
      vg.roundedRect(x, y+4, w + 10, StatusBarHeight-8, 3)
      vg.fillColor(gray(0.56))
      vg.fill()

      vg.fillColor(gray(0.2))
      discard vg.text(x + 5, ty, label)
      x += w + CommandLabelPadX
    else:
      let text = cmd
      vg.fillColor(gray(0.8))
      let tx = vg.text(x, ty, text)
      x = tx + CommandTextPadX

  vg.resetScissor()

# }}}

# {{{ isKeyDown()
func isKeyDown(ke: KeyEvent, keys: set[Key],
               mods: set[ModifierKey] = {}, repeat=false): bool =
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  ke.action in a and ke.key in keys and ke.mods == mods

func isKeyDown(ke: KeyEvent, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ke, {key}, mods, repeat)

func isKeyUp(ke: KeyEvent, keys: set[Key]): bool =
  ke.action == kaUp and ke.key in keys

# }}}
# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  a.cursorRow = 0
  a.cursorCol = 0
  a.drawMapParams.viewStartRow = 0
  a.drawMapParams.viewStartCol = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  dp.startX = MapLeftPad
  dp.startY = TitleBarHeight + a.mapTopPad

  var drawAreaHeight = winHeight - TitleBarHeight - StatusBarHeight -
                       a.mapTopPad - a.mapBottomPad

  if a.showNotesPane:
   drawAreaHeight -= NotesPaneTopPad + NotesPaneHeight + NotesPaneBottomPad

  let
    drawAreaWidth = winWidth - MapLeftPad - MapRightPad

  dp.viewRows = min(dp.numDisplayableRows(drawAreaHeight), a.map.rows)
  dp.viewCols = min(dp.numDisplayableCols(drawAreaWidth), a.map.cols)

  dp.viewStartRow = min(max(a.map.rows - dp.viewRows, 0), dp.viewStartRow)
  dp.viewStartCol = min(max(a.map.cols - dp.viewCols, 0), dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  a.cursorRow = min(
    max(viewEndRow, dp.viewStartRow),
    a.cursorRow
  )
  a.cursorCol = min(
    max(viewEndCol, dp.viewStartCol),
    a.cursorCol
  )

# }}}
# {{{ showCellCoords()
proc showCellCoords(show: bool, a) =
  alias(dp, a.drawMapParams)

  if show:
    a.mapTopPad = MapTopPadCoords
    a.mapBottomPad = MapBottomPadCoords
    dp.drawCellCoords = true
  else:
    a.mapTopPad = MapTopPadNoCoords
    a.mapBottomPad = MapBottomPadNoCoords
    dp.drawCellCoords = false

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, a) =
  alias(dp, a.drawMapParams)

  var
    cx = a.cursorCol
    cy = a.cursorRow
    sx = dp.viewStartCol
    sy = dp.viewStartRow

  case dir:
  of dirE:
    cx = min(cx+1, a.map.cols-1)
    if cx - sx > dp.viewCols-1 - a.scrollMargin:
      sx = min(max(a.map.cols - dp.viewCols, 0), sx+1)

  of dirS:
    cy = min(cy+1, a.map.rows-1)
    if cy - sy > dp.viewRows-1 - a.scrollMargin:
      sy = min(max(a.map.rows - dp.viewRows, 0), sy+1)

  of dirW:
    cx = max(cx-1, 0)
    if cx < sx + a.scrollMargin:
      sx = max(sx-1, 0)

  of dirN:
    cy = max(cy-1, 0)
    if cy < sy + a.scrollMargin:
      sy = max(sy-1, 0)

  a.cursorRow = cy
  a.cursorCol = cx
  dp.viewStartRow = sy
  dp.viewStartCol = sx

# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelectDraw
  a.selection = some(newSelection(a.map.rows, a.map.cols))
  a.drawMapParams.drawCursorGuides = true
  setStatusMessage(IconSelection, "Mark selection",
                   @["D", "draw", "E", "erase", "R", "rectangle",
                     "Ctrl+A/D", "mark/unmark all", "C", "copy", "X", "cut",
                     "Esc", "exit"], a)

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.editMode = emNormal
  a.selection = Selection.none
  a.drawMapParams.drawCursorGuides = false
  a.clearStatusMessage()

# }}}
# {{{ copySelection()
proc copySelection(a): Option[Rect[Natural]] =

  proc eraseOrphanedWalls(cb: CopyBuffer) =
    var m = cb.map
    for r in 0..<m.rows:
      for c in 0..<m.cols:
        m.eraseOrphanedWalls(r,c)

  let sel = a.selection.get

  let bbox = sel.boundingBox()
  if bbox.isSome:
    a.copyBuf = some(CopyBuffer(
      selection: newSelectionFrom(a.selection.get, bbox.get),
      map: newMapFrom(a.map, bbox.get)
    ))
    eraseOrphanedWalls(a.copyBuf.get)

  result = bbox

# }}}

# {{{ Dialogs

# {{{ New map dialog
var
  g_newMapDialogOpen: bool
  g_newMapDialog_name: string
  g_newMapDialog_rows: string
  g_newMapDialog_cols: string

proc newMapDialog(a) =
  koi.beginDialog(350, 220, fmt"{IconNewFile}  New map")
  a.clearStatusMessage()

  let
    dialogWidth = 350.0
    dialogHeight = 220.0
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Name", gray(0.80), fontSize=14.0)
  g_newMapDialog_name = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", g_newMapDialog_name
  )

  y = y + 50
  koi.label(x, y, labelWidth, h, "Rows", gray(0.80), fontSize=14.0)
  g_newMapDialog_rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_rows
  )

  y = y + 30
  koi.label(x, y, labelWidth, h, "Columns", gray(0.80), fontSize=14.0)
  g_newMapDialog_cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_cols
  )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(a) =
    initUndoManager(a.undoManager)
    # TODO number error checking
    let rows = parseInt(g_newMapDialog_rows)
    let cols = parseInt(g_newMapDialog_cols)
    a.map = newMap(rows, cols)
    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, fmt"New {rows}x{cols} map created", a)
    koi.closeDialog()
    g_newMapDialogOpen = false

  proc cancelAction(a) =
    koi.closeDialog()
    g_newMapDialogOpen = false


  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(a)

  koi.endDialog()

# }}}
# {{{ Edit note dialog
var
  g_editNoteDialogOpen: bool
  g_editNoteDialog_type: int
  g_editNoteDialog_customId: string
  g_editNoteDialog_note: string

proc editNoteDialog(a) =
  koi.beginDialog(450, 220, fmt"{IconCommentInv}  Edit Note")
  a.clearStatusMessage()

  let
    dialogWidth = 450.0
    dialogHeight = 220.0
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Type", gray(0.80), fontSize=14.0)
  g_editNoteDialog_type = koi.radioButtons(
    x + labelWidth, y, 232, h,
    labels = @["Number", "Custom", "Comment"],
    tooltips = @["", "", ""],
    g_editNoteDialog_type
  )

  y = y + 40
  koi.label(x, y, labelWidth, h, "Note", gray(0.80), fontSize=14.0)
  g_editNoteDialog_note = koi.textField(
    x + labelWidth, y, 320.0, h, tooltip = "", g_editNoteDialog_note
  )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(a) =
    koi.closeDialog()
    var note = Note(
      kind: NoteKind(g_editNoteDialog_type),
      text: g_editNoteDialog_note
    )
    actions.setNote(a.map, a.cursorRow, a.cursorCol, note, a.undoManager)
    setStatusMessage(IconComment, "Set cell note", a)
    g_editNoteDialogOpen = false

  proc cancelAction(a) =
    koi.closeDialog()
    g_editNoteDialogOpen = false

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(a)

  koi.endDialog()

# }}}

# }}}

# {{{ drawNotesPane()
proc drawNotesPane(x, y, w, h: float, a) =
  alias(vg, a.vg)
  alias(m, a.map)
  alias(ms, a.mapStyle)

  let curRow = a.cursorRow
  let curCol = a.cursorCol

  # TODO
  #[
  vg.beginPath()
  vg.fillColor(white(0.2))
  vg.rect(x, y, w, h)
  vg.fill()
]#

  if a.editMode != emPastePreview and m.hasNote(curRow, curCol):
    let note = m.getNote(curRow, curCol)

    vg.fillColor(ms.noteTextColor)

    case note.kind
    of nkIndexed:
      vg.setFont(20.0, "deco", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-3, $note.index)

    of nkCustomId:
      vg.setFont(20.0, "deco", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-3, note.customId)

    of nkComment:
      vg.setFont(18.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-19, y-2, IconComment)
#      vg.setFont(20.0, "deco", horizAlign=haCenter, vertAlign=vaTop)
#      discard vg.text(x-20, y-3, "A")

    vg.setFont(14.0, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.4)
    vg.scissor(x, y, w, h)
    vg.textBox(x, y, w, note.text)
    vg.resetScissor()


# }}}
# {{{ drawWallToolbar
const SpecialWalls = @[
  wIllusoryWall,
  wInvisibleWall,
  wDoor,
  wLockedDoor,
  wArchway,
  wSecretDoor,
  wLever,
  wNiche,
  wStatue
]

proc drawWallToolbar(x: float, a) =
  alias(vg, a.vg)
  alias(ms, a.mapStyle)
  alias(dp, a.toolbarDrawParams)

  proc drawWallTool(x, y: float, w: Wall, ctx: DrawMapContext) =
    case w
    of wNone:          discard
    of wWall:          drawSolidWallHoriz(x, y, ctx)
    of wIllusoryWall:  drawIllusoryWallHoriz(x, y, ctx)
    of wInvisibleWall: drawInvisibleWallHoriz(x, y, ctx)
    of wDoor:          drawDoorHoriz(x, y, ctx)
    of wLockedDoor:    drawLockedDoorHoriz(x, y, ctx)
    of wArchway:       drawArchwayHoriz(x, y, ctx)
    of wSecretDoor:    drawSecretDoorHoriz(x, y, ctx)
    of wLever:         discard
    of wNiche:         discard
    of wStatue:        discard

  dp.setZoomLevel(ms, 1)
  let ctx = DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg)

  let
    toolPad = 4.0
    w = dp.gridSize + toolPad*2
    yPad = 2.0

  var y = 100.0

  for i, wall in SpecialWalls.pairs:
    if i == a.currSpecialWallIdx:
      vg.fillColor(rgb(1.0, 0.7, 0))
    else:
      vg.fillColor(gray(0.6))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()

    drawWallTool(x+toolPad, y+toolPad + dp.gridSize*0.5, wall, ctx)
    y += w + yPad

# }}}
# {{{ drawMarkerIconToolbar()
proc drawMarkerIconToolbar(x: float, a) =
  alias(vg, a.vg)
  alias(ms, a.mapStyle)
  alias(dp, a.toolbarDrawParams)

  dp.setZoomLevel(ms, 5)
  let ctx = DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg)

  let
    toolPad = 0.0
    w = dp.gridSize + toolPad*2
    yPad = 2.0

  var
    x = x
    y = 100.0

  for i, icon in MarkerIcons.pairs:
    if i > 0 and i mod 3 == 0:
      y = 100.0
      x += w + yPad

    vg.fillColor(gray(0.6))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()

    drawIcon(x+toolPad, y+toolPad, 0, 0, icon, ctx)
    y += w + yPad

# }}}

# {{{ handleMapEvents()
proc handleMapEvents(a) =
  alias(curRow, a.cursorRow)
  alias(curCol, a.cursorCol)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(ms, a.mapStyle)
  alias(dp, a.drawMapParams)
  alias(win, a.win)

  proc mkFloorMessage(f: Floor): string =
    fmt"Set floor – {f}"

  proc setFloorOrientationStatusMessage(o: Orientation, a) =
    if o == Horiz:
      setStatusMessage(IconHorizArrows, "Floor orientation set to horizontal", a)
    else:
      setStatusMessage(IconVertArrows, "Floor orientation set to vertical", a)

  proc incZoomLevel(a) =
    incZoomLevel(ms, dp)
    updateViewStartAndCursorPosition(a)

  proc decZoomLevel(a) =
    decZoomLevel(ms, dp)
    updateViewStartAndCursorPosition(a)

  proc cycleFloor(f, first, last: Floor): Floor =
    if f >= first and f <= last:
      result = Floor(ord(f) + 1)
      if result > last: result = first
    else:
      result = first

  proc setFloor(first, last: Floor, a) =
    var f = m.getFloor(curRow, curCol)
    f = cycleFloor(f, first, last)
    let ot = m.guessFloorOrientation(curRow, curCol)
    actions.setOrientedFloor(m, curRow, curCol, f, ot, um)
    setStatusMessage(mkFloorMessage(f), a)

  let (winWidth, winHeight) = win.size

  const
    MoveKeysLeft  = {keyLeft,  keyH, keyKp4}
    MoveKeysRight = {keyRight, keyL, keyKp6}
    MoveKeysUp    = {keyUp,    keyK, keyKp8}
    MoveKeysDown  = {keyDown,  keyJ, keyKp2}

  # TODO these should be part of the map component event handler
  for ke in koi.keyBuf():
    case a.editMode:
    of emNormal:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      if ke.isKeyDown(keyLeft, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w - 10, h)
      elif ke.isKeyDown(keyRight, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w + 10, h)

      elif ke.isKeyDown(keyD):
        a.editMode = emExcavate
        setStatusMessage(IconPencil, "Excavate tunnel",
                         @[IconArrows, "draw"], a)
        actions.excavate(m, curRow, curCol, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        setStatusMessage(IconEraser, "Erase cells", @[IconArrows, "erase"], a)
        actions.eraseCell(m, curRow, curCol, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearFloor
        setStatusMessage(IconEraser, "Clear floor",  @[IconArrows, "clear"], a)
        actions.setFloor(m, curRow, curCol, fEmpty, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(m, curRow, curCol, um)
        setFloorOrientationStatusMessage(m.getFloorOrientation(curRow, curCol), a)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall
        setStatusMessage("", "Draw walls", @[IconArrows, "set/clear"], a)

      elif ke.isKeyDown(keyR):
        a.editMode = emDrawWallSpecial
        setStatusMessage("", "Draw wall special", @[IconArrows, "set/clear"], a)

      # TODO
#      elif ke.isKeyDown(keyW) and ke.mods == {mkAlt}:
#        actions.eraseCellWalls(m, curRow, curCol, um)

      elif ke.isKeyDown(key1):
        setFloor(fDoor, fSecretDoor, a)

      elif ke.isKeyDown(key2):
        setFloor(fDoor, fSecretDoor, a)

      elif ke.isKeyDown(key3):
        setFloor(fPressurePlate, fHiddenPressurePlate, a)

      elif ke.isKeyDown(key4):
        setFloor(fClosedPit, fCeilingPit, a)

      elif ke.isKeyDown(key5):
        setFloor(fStairsDown, fStairsUp, a)

      elif ke.isKeyDown(key6):
        let f = fSpinner
        actions.setFloor(m, curRow, curCol, f, um)
        setStatusMessage(mkFloorMessage(f), a)

      elif ke.isKeyDown(key7):
        let f = fTeleport
        actions.setFloor(m, curRow, curCol, f, um)
        setStatusMessage(mkFloorMessage(f), a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if a.currSpecialWallIdx > 0: dec(a.currSpecialWallIdx)
        else: a.currSpecialWallIdx = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if a.currSpecialWallIdx < SpecialWalls.high: inc(a.currSpecialWallIdx)
        else: a.currSpecialWallIdx = 0

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true):
        um.undo(m)
        setStatusMessage(IconUndo, "Undid action", a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        um.redo(m)
        setStatusMessage(IconRedo, "Redid action", a)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if a.copyBuf.isSome:
          actions.paste(m, curRow, curCol, a.copyBuf.get, um)
          setStatusMessage(IconPaste, "Pasted buffer", a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyP, {mkShift}):
        if a.copyBuf.isSome:
          a.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrows, "placement",
                           "Enter/P", "paste", "Esc", "exit"], a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyEqual, repeat=true):
        incZoomLevel(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        decZoomLevel(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyN):
        if m.getFloor(curRow, curCol) == fNone:
          setStatusMessage(IconWarning, "Cannot attach note to empty cell", a)
        else:
          if m.hasNote(curRow, curCol):
            let note = m.getNote(curRow, curCol)
            g_editNoteDialog_type = ord(note.kind)
            g_editNoteDialog_note = note.text
          else:
            g_editNoteDialog_type = ord(nkComment)
            g_editNoteDialog_note = ""
          g_editNoteDialogOpen = true

      elif ke.isKeyDown(keyN, {mkCtrl}):
        g_newMapDialog_name = "Level 1"
        g_newMapDialog_rows = $m.rows
        g_newMapDialog_cols = $m.cols
        g_newMapDialogOpen = true

      elif ke.isKeyDown(keyO, {mkCtrl}):
        when not defined(DEBUG):
          let ext = MapFileExtension
          let filename = fileDialog(fdOpenFile,
                                    filters=fmt"Gridmonger Map (*.{ext}):{ext}")
          if filename != "":
            try:
              m = readMap(filename)
              initUndoManager(um)
              resetCursorAndViewStart(a)
              updateViewStartAndCursorPosition(a)
              setStatusMessage(IconFloppy, fmt"Map '{filename}' loaded", a)
            except CatchableError as e:
              # TODO log stracktrace?
              setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)

      elif ke.isKeyDown(keyS, {mkCtrl}):
        when not defined(DEBUG):
          let ext = MapFileExtension
          var filename = fileDialog(fdSaveFile,
                                    filters=fmt"Gridmonger Map (*.{ext}):{ext}")
          if filename != "":
            try:
              filename = addFileExt(filename, ext)
              writeMap(m, filename)
              setStatusMessage(IconFloppy, fmt"Map saved", a)
            except CatchableError as e:
              # TODO log stracktrace?
              setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}", a)

      elif ke.isKeyDown(keyR, {mkAlt,mkCtrl}):
        a.nextThemeIndex = a.currThemeIndex.some
        koi.incFramesLeft()

      elif ke.isKeyDown(keyPageUp, {mkAlt,mkCtrl}):
        var i = a.currThemeIndex
        if i == 0: i = a.themeNames.high else: dec(i)
        a.nextThemeIndex = i.some
        koi.incFramesLeft()

      elif ke.isKeyDown(keyPageDown, {mkAlt,mkCtrl}):
        var i = a.currThemeIndex
        inc(i)
        if i > a.themeNames.high: i = 0
        a.nextThemeIndex = i.some
        koi.incFramesLeft()

      # Toggle options
      elif ke.isKeyDown(keyC, {mkAlt}):
        var state: string
        if dp.drawCellCoords:
          showCellCoords(false, a)
          state = "off"
        else:
          showCellCoords(true, a)
          state = "on"

        updateViewStartAndCursorPosition(a)
        setStatusMessage(fmt"Cell coordinates turned {state}", a)

      elif ke.isKeyDown(keyN, {mkAlt}):
        if a.showNotesPane:
          setStatusMessage(fmt"Notes pane shown", a)
          a.showNotesPane = false
        else:
          setStatusMessage(fmt"Notes pane hidden", a)
          a.showNotesPane = true

        updateViewStartAndCursorPosition(a)

    of emExcavate, emEraseCell, emClearFloor:
      proc handleMoveKey(dir: CardinalDir, a) =
        if a.editMode == emExcavate:
          moveCursor(dir, a)
          actions.excavate(m, curRow, curCol, um)

        elif a.editMode == emEraseCell:
          moveCursor(dir, a)
          actions.eraseCell(m, curRow, curCol, um)

        elif a.editMode == emClearFloor:
          moveCursor(dir, a)
          actions.setFloor(m, curRow, curCol, fEmpty, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(m, curRow, curCol, dir):
          let w = if m.getWall(curRow, curCol, dir) == wNone: wWall
                  else: wNone
          actions.setWall(m, curRow, curCol, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyW}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWallSpecial:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(m, curRow, curCol, dir):
          let curSpecWall = SpecialWalls[a.currSpecialWallIdx]
          let w = if m.getWall(curRow, curCol, dir) == curSpecWall: wNone
                  else: curSpecWall
          actions.setWall(m, curRow, curCol, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyR}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emSelectDraw:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      # TODO don't use win
      if   win.isKeyDown(keyD): a.selection.get[curRow, curCol] = true
      elif win.isKeyDown(keyE): a.selection.get[curRow, curCol] = false

      if   ke.isKeyDown(keyA, {mkCtrl}): a.selection.get.fill(true)
      elif ke.isKeyDown(keyD, {mkCtrl}): a.selection.get.fill(false)

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          startRow: curRow,
          startCol: curCol,
          rect: rectN(curRow, curCol, curRow+1, curCol+1),
          selected: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC):
        discard copySelection(a)
        exitSelectMode(a)
        setStatusMessage(IconCopy, "Copied to buffer", a)

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconCut, "Cut to buffer", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

    of emSelectRect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      var r1,c1, r2,c2: Natural
      if a.selRect.get.startRow <= curRow:
        r1 = a.selRect.get.startRow
        r2 = curRow+1
      else:
        r1 = curRow
        r2 = a.selRect.get.startRow + 1

      if a.selRect.get.startCol <= curCol:
        c1 = a.selRect.get.startCol
        c2 = curCol+1
      else:
        c1 = curCol
        c2 = a.selRect.get.startCol + 1

      a.selRect.get.rect = rectN(r1,c1, r2,c2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.selected)
        a.selRect = SelectionRect.none
        a.editMode = emSelectDraw

    of emPastePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(m, curRow, curCol, a.copyBuf.get, um)
        a.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        a.editMode = emNormal
        a.clearStatusMessage()
# }}}

# {{{ renderUI()
proc renderUI() =
  alias(a, g_app)
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  alias(vg, a.vg)

  # Clear background
  vg.beginPath()
  vg.rect(0, TitleBarHeight, winWidth.float, winHeight.float - TitleBarHeight)
  # TODO
  vg.fillColor(a.mapStyle.backgroundColor)
  vg.fill()

  # Current level dropdown
  a.currMapLevel = koi.dropdown(
    MapLeftPad, 45, 300, 24.0,   # TODO calc y
    items = @[
      "Level 1 - Legend of Darkmoor",
      "The Beginning",
      "The Dwarf Settlement",
      "You Only Scream Twice"
    ],
    tooltip = "Current map level",
    a.currMapLevel)

  # Map
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = a.cursorRow
    dp.cursorCol = a.cursorCol

    dp.selection = a.selection
    dp.selRect = a.selRect
    dp.pastePreview = if a.editMode == emPastePreview: a.copyBuf
                      else: CopyBuffer.none

    drawMap(a.map, DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg))

  if a.showNotesPane:
    drawNotesPane(
      x = MapLeftPad,
      y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
      w = winWidth - MapLeftPad*2,  # TODO
      h = NotesPaneHeight,
      a
    )

  # Toolbar
#  drawMarkerIconToolbar(winWidth - 400.0, a)
  drawWallToolBar(winWidth - 60.0, a)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, winWidth.float, a)

  # Dialogs
  if g_newMapDialogOpen:     newMapDialog(a)
  elif g_editNoteDialogOpen: editNoteDialog(a)

# }}}
# {{{ renderFramePre()
proc renderFramePre(win: CSDWindow) =
  alias(a, g_app)
  alias(vg, g_app.vg)

  if a.nextThemeIndex.isSome:
    let themeIndex = a.nextThemeIndex.get
    a.themeReloaded = themeIndex == a.currThemeIndex
    loadTheme(themeIndex, a)
    a.drawMapParams.initDrawMapParams(a.mapStyle, a.vg, getPxRatio(a))
    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message

# }}}
# {{{ renderFrame()
proc renderFrame(win: CSDWindow, doHandleEvents: bool = true) =
  alias(a, g_app)
  alias(vg, g_app.vg)

  if a.nextThemeIndex.isSome:
    let themeName = a.themeNames[a.currThemeIndex]
    if a.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
    else:
      setStatusMessage(fmt"Switched to '{themeName}' theme", a)
    a.nextThemeIndex = Natural.none

  updateViewStartAndCursorPosition(a)

  if doHandleEvents:
    handleMapEvents(a)

  renderUI()

# }}}

# {{{ Init & cleanup
proc initDrawMapParams(a) =
  alias(dp, a.drawMapParams)
  dp = newDrawMapParams()
  dp.drawCellCoords   = true
  dp.drawCursorGuides = false
  dp.initDrawMapParams(a.mapStyle, a.vg, getPxRatio(a))


proc loadFonts(vg: NVGContext) =
  # TODO fix font load error checking
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add regular font.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add bold font.\n"

  let decoFont = vg.createFont("deco", "data/Grenze-Bold.ttf")
  if decoFont == NoFont:
    quit "Could not add deco font.\n"

  let iconFont = vg.createFont("icon", "data/GridmongerIcons.ttf")
  if iconFont == NoFont:
    quit "Could not load icon font.\n"

  discard addFallbackFont(vg, regularFont, iconFont)
  discard addFallbackFont(vg, boldFont, iconFont)
  discard addFallbackFont(vg, decoFont, iconFont)


# TODO clean up
proc initGfx(): (CSDWindow, NVGContext) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  let vg = nvgInit(getProcAddress, {nifStencilStrokes, nifAntialias})
  if vg == nil:
    quit "Error creating NanoVG context"

  loadFonts(vg)

  koi.init(vg)

  result = (win, vg)


proc initApp(win: CSDWindow, vg: NVGContext) =
  alias(a, g_app)

  a = new AppContext
  a.win = win
  a.vg = vg
  a.undoManager = newUndoManager[Map]()

  searchThemes(a)
  var themeIndex = findThemeIndex("light", a)
  if themeIndex == -1:
    themeIndex = 0
  loadTheme(themeIndex, a)

  initDrawMapParams(a)
  a.drawMapParams.setZoomLevel(a.mapStyle, DefaultZoomLevel)
  a.scrollMargin = 3

  a.toolbarDrawParams = a.drawMapParams.deepCopy
  a.toolbarDrawParams.setZoomLevel(a.mapStyle, 1)

  showCellCoords(true, a)
  a.showNotesPane = true

  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

#  a.map = newMap(16, 16)
  a.map = readMap("EOB III - Crystal Tower L2 notes.grm")
#  a.map = readMap("drawtest.grm")
#  a.map = readMap("notetest.grm")

  a.win.renderFramePreCb = renderFramePre
  a.win.renderFrameCb = renderFrame

  a.win.title = "Eye of the Beholder III"
  a.win.modified = true
  # TODO for development
  a.win.size = (960, 1040)
  a.win.pos = (960, 0)
  a.win.show()


proc cleanup() =
  koi.deinit()
  nvgDeinit(g_app.vg)
  glfw.terminate()

# }}}

proc main() =
  let (win, vg) = initGfx()
  initApp(win, vg)

  while not g_app.win.shouldClose:
    if koi.shouldRenderNextFrame():
      glfw.pollEvents()
    else:
      glfw.waitEvents()
    csdRenderFrame(g_app.win)
  cleanup()

main()

# vim: et:ts=2:sw=2:fdm=marker
