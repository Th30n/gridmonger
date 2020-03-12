import lenientops
import math
import options
import strutils
import strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg
import osdialog

import actions
import common
import drawmap
import map
import persistence
import selection
import undomanager
import utils


const DefaultZoomLevel = 5

# {{{ AppContext
type
  EditMode* = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearGround,
    emSelectDraw,
    emSelectRect
    emPastePreview

  AppContext = ref object
    # Context
    win:            Window
    vg:             NVGContext

    # Dependencies
    undoManager:    UndoManager[Map]

    # Document (group under 'doc'?)
    map:            Map

    # Options (group under 'opts'?)
    scrollMargin:   Natural
    mapStyle:       MapStyle

    # UI state (group under 'ui'?)
    editMode:       EditMode
    cursorCol:      Natural
    cursorRow:      Natural

    currWall:       Wall

    selection:      Option[Selection]
    selRect:        Option[SelectionRect]
    copyBuf:        Option[CopyBuffer]

    drawMapParams:  DrawMapParams


var g_app: AppContext

using a: var AppContext

# }}}

# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  a.cursorCol = 0
  a.cursorRow = 0
  a.drawMapParams.viewStartCol = 0
  a.drawMapParams.viewStartRow = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  # TODO -150
  dp.viewCols = min(dp.numDisplayableCols(winWidth - 150.0), a.map.cols)
  dp.viewRows = min(dp.numDisplayableRows(winHeight - 150.0), a.map.rows)

  dp.viewStartCol = min(max(a.map.cols - dp.viewCols, 0), dp.viewStartCol)
  dp.viewStartRow = min(max(a.map.rows - dp.viewRows, 0), dp.viewStartRow)

  let viewEndCol = dp.viewStartCol + dp.viewCols - 1
  let viewEndRow = dp.viewStartRow + dp.viewRows - 1

  a.cursorCol = min(
    max(viewEndCol, dp.viewStartCol),
    a.cursorCol
  )
  a.cursorRow = min(
    max(viewEndRow, dp.viewStartRow),
    a.cursorRow
  )

# }}}
# {{{ moveCursor()
proc moveCursor(dir: Direction, a) =
  alias(dp, a.drawMapParams)

  var
    cx = a.cursorCol
    cy = a.cursorRow
    sx = dp.viewStartCol
    sy = dp.viewStartRow

  case dir:
  of East:
    cx = min(cx+1, a.map.cols-1)
    if cx - sx > dp.viewCols-1 - a.scrollMargin:
      sx = min(max(a.map.cols - dp.viewCols, 0), sx+1)

  of South:
    cy = min(cy+1, a.map.rows-1)
    if cy - sy > dp.viewRows-1 - a.scrollMargin:
      sy = min(max(a.map.rows - dp.viewRows, 0), sy+1)

  of West:
    cx = max(cx-1, 0)
    if cx < sx + a.scrollMargin:
      sx = max(sx-1, 0)

  of North:
    cy = max(cy-1, 0)
    if cy < sy + a.scrollMargin:
      sy = max(sy-1, 0)

  a.cursorCol = cx
  a.cursorRow = cy
  dp.viewStartCol = sx
  dp.viewStartRow = sy

# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelectDraw
  a.selection = some(newSelection(a.map.cols, a.map.rows))
  a.drawMapParams.drawCursorGuides = true

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.editMode = emNormal
  a.selection = none(Selection)
  a.drawMapParams.drawCursorGuides = false

# }}}
# {{{ copySelection()
proc copySelection(a): Option[Rect[Natural]] =

  proc eraseOrphanedWalls(cb: CopyBuffer) =
    var m = cb.map
    for c in 0..<m.cols:
      for r in 0..<m.rows:
        m.eraseOrphanedWalls(c,r)

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

# {{{ Dialogs

# {{{ New map dialog
const NewMapDialogTitle = "New map"

var
  g_newMapDialog_name: string
  g_newMapDialog_cols: string
  g_newMapDialog_rows: string

proc newMapDialog() =
  koi.dialog(350, 220, NewMapDialogTitle):
    let
      dialogWidth = 350.0
      dialogHeight = 220.0
      h = 24.0
      labelWidth = 70.0
      buttonWidth = 70.0
      buttonPad = 15.0

    var
      x = 30.0
      y = 60.0

    koi.label(x, y, labelWidth, h, "Name", gray(0.70), fontSize=14.0)
    g_newMapDialog_name = koi.textField(
      x + labelWidth, y, 220.0, h, tooltip = "", g_newMapDialog_name
    )

    y = y + 50
    koi.label(x, y, labelWidth, h, "Columns", gray(0.70), fontSize=14.0)
    g_newMapDialog_cols = koi.textField(
      x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_cols
    )

    y = y + 30
    koi.label(x, y, labelWidth, h, "Rows", gray(0.70), fontSize=14.0)
    g_newMapDialog_rows = koi.textField(
      x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_rows
    )

    x = dialogWidth - 2 * buttonWidth - buttonPad - 10
    y = dialogHeight - h - buttonPad

    let okAction = proc () =
      initUndoManager(g_app.undoManager)
      g_app.map = newMap(
        parseInt(g_newMapDialog_cols),
        parseInt(g_newMapDialog_rows)
      )
      resetCursorAndViewStart(g_app)
      closeDialog()

    let cancelAction = proc () =
      closeDialog()

    if koi.button(x, y, buttonWidth, h, "OK", color = gray(0.4)):
      okAction()

    x += buttonWidth + 10
    if koi.button(x, y, buttonWidth, h, "Cancel", color = gray(0.4)):
      cancelAction()

    for ke in koi.keyBuf():
      if ke.action == kaDown and ke.key == keyEscape:
        cancelAction()
      elif ke.action == kaDown and ke.key == keyEnter:
        okAction()

# }}}

template defineDialogs() =
  newMapDialog()

# }}}

proc drawWallTool(a) =
  alias(vg, a.vg)
  let xs = 600.0
  let ys = 100.0
  let w = 25.0
  let pad = 8.0

  var
    x = xs
    y = ys

  for wall in wIllusoryWall..wStatue:
    if a.currWall == wall:
      vg.fillColor(rgb(1.0, 0.7, 0))
    else:
      vg.fillColor(gray(0.3))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()
    y += w + pad

# {{{ handleEvents()
proc handleEvents(a) =
  alias(curX, a.cursorCol)
  alias(curY, a.cursorRow)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(win, a.win)

  const
    MoveKeysLeft  = {keyLeft,  keyH, keyKp4}
    MoveKeysRight = {keyRight, keyL, keyKp6}
    MoveKeysUp    = {keyUp,    keyK, keyKp8}
    MoveKeysDown  = {keyDown,  keyJ, keyKp2}

  for ke in koi.keyBuf():
    case a.editMode:
    of emNormal:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      if ke.isKeyDown(keyD):
        a.editMode = emExcavate
        actions.excavate(m, curX, curY, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        actions.eraseCell(m, curX, curY, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearGround
        actions.setGround(m, curX, curY, gEmpty, um)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall

      elif ke.isKeyDown(keyR):
        a.editMode = emDrawWallSpecial

      elif ke.isKeyDown(keyW) and ke.mods == {mkAlt}:
        actions.eraseCellWalls(m, curX, curY, um)

      elif ke.isKeyDown(key1):
        if m.getGround(curX, curY) == gClosedDoor:
          actions.toggleGroundOrientation(m, curX, curY, um)
        else:
          actions.setGround(m, curX, curY, gClosedDoor, um)

      elif ke.isKeyDown(key2):
        if m.getGround(curX, curY) == gOpenDoor:
          actions.toggleGroundOrientation(m, curX, curY, um)
        else:
          actions.setGround(m, curX, curY, gOpenDoor, um)

      elif ke.isKeyDown(key3):
        var g = m.getGround(curX, curY)
        g = if g == gPressurePlate: gHiddenPressurePlate else: gPressurePlate
        actions.setGround(m, curX, curY, g, um)

      elif ke.isKeyDown(key4):
        var g = m.getGround(curX, curY)
        if g >= gClosedPit and g <= gCeilingPit:
          g = Ground(ord(g) + 1)
          if g > gCeilingPit: g = gClosedPit
        else:
          g = gClosedPit
        actions.setGround(m, curX, curY, g, um)

      elif ke.isKeyDown(key5):
        var g = m.getGround(curX, curY)
        g = if g == gStairsDown: gStairsUp else: gStairsDown
        actions.setGround(m, curX, curY, g, um)

      elif ke.isKeyDown(key6):
        actions.setGround(m, curX, curY, gSpinner, um)

      elif ke.isKeyDown(key7):
        actions.setGround(m, curX, curY, gTeleport, um)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if a.currWall > wIllusoryWall: dec(a.currWall)
        else: a.currWall = a.currWall.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if a.currWall < Wall.high: inc(a.currWall)
        else: a.currWall = wIllusoryWall

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true):
        um.undo(m)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        um.redo(m)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if a.copyBuf.isSome:
          actions.paste(m, curX, curY, a.copyBuf.get, um)

      elif ke.isKeyDown(keyP, {mkShift}):
        if a.copyBuf.isSome:
          a.editMode = emPastePreview

      elif ke.isKeyDown(keyEqual, repeat=true):
        a.drawMapParams.incZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        a.drawMapParams.decZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        g_newMapDialog_name = "Level 1"
        g_newMapDialog_cols = $a.map.cols
        g_newMapDialog_rows = $a.map.rows
        openDialog(NewMapDialogTitle)

      elif ke.isKeyDown(keyO, {mkCtrl}):
        let filename = fileDialog(fdOpenFile, filters="Gridmonger Map:grm")
        if filename != "":
          try:
            a.map = readMap(filename)
            initUndoManager(a.undoManager)
            resetCursorAndViewStart(a)
          except CatchableError as e:
            # TODO handle error
            discard

      elif ke.isKeyDown(keyS, {mkCtrl}):
        let filename = fileDialog(fdSaveFile, filters="Gridmonger Map:grm")
        try:
          writeMap(a.map, filename)
        except CatchableError as e:
          # TODO handle error
          discard

    of emExcavate, emEraseCell, emClearGround:
      proc handleMoveKey(dir: Direction, a) =
        if a.editMode == emExcavate:
          moveCursor(dir, a)
          actions.excavate(m, curX, curY, um)

        elif a.editMode == emEraseCell:
          moveCursor(dir, a)
          actions.eraseCell(m, curX, curY, um)

        elif a.editMode == emClearGround:
          moveCursor(dir, a)
          actions.setGround(m, curX, curY, gEmpty, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(South, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        a.editMode = emNormal

    of emDrawWall:
      proc handleMoveKey(dir: Direction, a) =
        if canSetWall(m, curX, curY, dir):
          let w = if m.getWall(curX, curY, dir) == wNone: wWall
                  else: wNone
          actions.setWall(m, curX, curY, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(South, a)

      elif ke.isKeyUp({keyW}):
        a.editMode = emNormal

    of emDrawWallSpecial:
      proc handleMoveKey(dir: Direction, a) =
        if canSetWall(m, curX, curY, dir):
          let w = if m.getWall(curX, curY, dir) == a.currWall: wNone
                  else: a.currWall
          actions.setWall(m, curX, curY, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(South, a)

      elif ke.isKeyUp({keyR}):
        a.editMode = emNormal

    of emSelectDraw:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      if   win.isKeyDown(keyD): a.selection.get[curX, curY] = true
      elif win.isKeyDown(keyE): a.selection.get[curX, curY] = false

      if   ke.isKeyDown(keyA, {mkCtrl}): a.selection.get.fill(true)
      elif ke.isKeyDown(keyD, {mkCtrl}): a.selection.get.fill(false)

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          x0: curX, y0: curY,
          rect: rectN(curX, curY, curX+1, curY+1),
          fillValue: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC):
        discard copySelection(a)
        exitSelectMode(a)

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)

      elif ke.isKeyDown(keyEqual, repeat=true):
        a.drawMapParams.incZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        a.drawMapParams.decZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)

    of emSelectRect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      var x1, y1, x2, y2: Natural
      if a.selRect.get.x0 <= curX:
        x1 = a.selRect.get.x0
        x2 = curX+1
      else:
        x1 = curX
        x2 = a.selRect.get.x0 + 1

      if a.selRect.get.y0 <= curY:
        y1 = a.selRect.get.y0
        y2 = curY+1
      else:
        y1 = curY
        y2 = a.selRect.get.y0 + 1

      a.selRect.get.rect = rectN(x1, y1, x2, y2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.fillValue)
        a.selRect = none(SelectionRect)
        a.editMode = emSelectDraw

    of emPastePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(m, curX, curY, a.copyBuf.get, um)
        a.editMode = emNormal

      elif ke.isKeyDown(keyEqual, repeat=true):
        a.drawMapParams.incZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        a.drawMapParams.decZoomLevel()
        updateViewStartAndCursorPosition(a)

      elif ke.isKeyDown(keyEscape):
        a.editMode = emNormal

# }}}
# {{{ renderUI()

var g_textFieldVal1 = "Level 1"

proc renderUI() =
  alias(a, g_app)
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  if dp.viewCols > 0 and dp.viewRows > 0:
    dp.cursorCol = a.cursorCol
    dp.cursorRow = a.cursorRow

    dp.selection = a.selection
    dp.selRect = a.selRect
    dp.pastePreview = if a.editMode == emPastePreview: a.copyBuf
                      else: none(CopyBuffer)

    drawMap(a.map, DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg))
    drawWallTool(a)

  g_textFieldVal1 = koi.textField(
    winWidth-200.0, 30.0, 150.0, 24.0, tooltip = "Text field 1", g_textFieldVal1)

# }}}

# {{{ renderFrame()
proc renderFrame(win: Window, res: tuple[w, h: int32] = (0,0)) =
  alias(a, g_app)
  alias(vg, g_app.vg)

  let
    (winWidth, winHeight) = win.size
    (fbWidth, fbHeight) = win.framebufferSize
    pxRatio = fbWidth / winWidth

  # Update and render
  glViewport(0, 0, fbWidth, fbHeight)

  glClearColor(0.4, 0.4, 0.4, 1.0)

  glClear(GL_COLOR_BUFFER_BIT or
          GL_DEPTH_BUFFER_BIT or
          GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  ######################################################

  updateViewStartAndCursorPosition(a)
  defineDialogs()
  handleEvents(a)
  renderUI()

  ######################################################

  koi.endFrame()
  vg.endFrame()

  glfw.swapBuffers(win)

# }}}
# {{{ framebufSizeCb
proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  renderFrame(win)
  glfw.pollEvents()

# }}}

# {{{ init & cleanup
proc createDefaultMapStyle(): MapStyle =
  var ms = new MapStyle
  ms.cellCoordsColor     = gray(0.9)
  ms.cellCoordsColorHi   = rgb(1.0, 0.75, 0.0)
  ms.cellCoordsFontSize  = 12.0
  ms.cursorColor         = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor    = rgba(1.0, 0.65, 0.0, 0.2)
  ms.defaultFgColor      = gray(0.1)
  ms.groundColor         = gray(0.9)
  ms.gridColorBackground = gray(0.0, 0.3)
  ms.gridColorGround     = gray(0.0, 0.2)
  ms.mapBackgroundColor  = gray(0.0, 0.7)
  ms.mapOutlineColor     = gray(0.23)
  ms.selectionColor      = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor   = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms

proc initDrawMapParams(a) =
  alias(dp, a.drawMapParams)

  dp.startX = 50.0
  dp.startY = 50.0
  dp.drawOutline         = false
  dp.drawCursorGuides    = false


proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 800, h: 800)
  cfg.title = "Gridmonger v0.1"
  cfg.resizable = true
  cfg.visible = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = true
  cfg.nMultiSamples = 4

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  newWindow(cfg)


proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add regular font.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add bold font.\n"


proc init(): Window =
  g_app = new AppContext

  glfw.initialize()

  var win = createWindow()
  g_app.win = win

  var flags = {nifStencilStrokes, nifDebug}
  g_app.vg = nvgInit(getProcAddress, flags)
  if g_app.vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(g_app.vg)

  g_app.map = newMap(16, 16)
  g_app.mapStyle = createDefaultMapStyle()
  g_app.undoManager = newUndoManager[Map]()
  g_app.currWall = wIllusoryWall

  g_app.drawMapParams = new DrawMapParams
  initDrawMapParams(g_app)
  g_app.drawMapParams.setZoomLevel(DefaultZoomLevel)

  g_app.scrollMargin = 3

  koi.init(g_app.vg)

  win.framebufferSizeCb = framebufSizeCb

  glfw.swapInterval(1)

  win.pos = (150, 150)  # TODO for development
  wrapper.showWindow(win.getHandle())

  result = win


proc cleanup() =
  koi.deinit()
  nvgDeinit(g_app.vg)
  glfw.terminate()

# }}}

proc main() =
  let win = init()

  while not win.shouldClose:
    renderFrame(win)
    glfw.pollEvents()

  cleanup()


main()


# vim: et:ts=2:sw=2:fdm=marker
