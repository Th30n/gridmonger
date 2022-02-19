# {{{ Imports

import algorithm
import browsers
import lenientops
import logging
import macros
import math
import options
import os
import sequtils
import std/monotimes
import streams
import strformat
import strutils
import tables
import times

import deps/with
import glad/gl
import glfw
from glfw/wrapper import IconImageObj
import koi
import koi/undomanager
from koi/utils as koiUtils import lerp, invLerp
import nanovg
when not defined(DEBUG): import osdialog

import actions
import cfghelper
import cmdline
import common
import csdwindow
import drawlevel
import fieldlimits
import hocon
import icons
import level
import map
import persistence
import rect
import selection
import theme
import unicode
import utils

when defined(windows):
  import platform/windows/ipc
  import platform/windows/console

# }}}

# {{{ Resources

when defined(windows):
  const arch = when defined(i386): "32" else: "64"
  {.link: fmt"extras/appicons/windows/gridmonger{arch}.res".}

# }}}

# {{{ Constants
const
  ThemeExt = "gmtheme"
  MapFileExt = "gmm"
  BackupFileExt = "bak"

when not defined(DEBUG):
  const
    GridmongerMapFileFilter = fmt"Gridmonger Map (*.{MapFileExt}):{MapFileExt}"

    CrashAutosaveFilename = addFileExt("Crash Autosave", MapFileExt)

const
  CursorJump   = 5
  ScrollMargin = 3

const
  StatusBarHeight         = 26.0

  LevelTopPad_Regions     = 28.0

  LevelTopPad_Coords      = 85.0
  LevelRightPad_Coords    = 50.0
  LevelBottomPad_Coords   = 40.0
  LevelLeftPad_Coords     = 50.0

  LevelTopPad_NoCoords    = 65.0
  LevelRightPad_NoCoords  = 28.0
  LevelBottomPad_NoCoords = 10.0
  LevelLeftPad_NoCoords   = 28.0

  NotesPaneHeight         = 62.0
  NotesPaneTopPad         = 10.0
  NotesPaneRightPad       = 50.0
  NotesPaneBottomPad      = 10.0
  NotesPaneLeftPad        = 20.0

  ToolsPaneWidthNarrow    = 60.0
  ToolsPaneWidthWide      = 90.0
  ToolsPaneTopPad         = 65.0
  ToolsPaneBottomPad      = 30.0
  ToolsPaneYBreakpoint1   = 709.0
  ToolsPaneYBreakpoint2   = 859.0

  ThemePaneWidth          = 326.0

const
  SplashTimeoutSecsLimits* = intLimits(min=1, max=10)
  AutosaveFreqMinsLimits*  = intLimits(min=1, max=30)
  WindowWidthLimits*       = intLimits(WindowMinWidth, max=20_000)
  WindowHeightLimits*      = intLimits(WindowMinHeight, max=20_000)

const
  WarningMessageTimeout = initDuration(seconds = 3)
  InfiniteDuration      = initDuration(seconds = int64.high)

const
  SpecialWalls = @[
    wDoor,
    wLockedDoor,
    wArchway,
    wSecretDoor,
    wOneWayDoorNE,
    wIllusoryWall,
    wInvisibleWall,
    wLeverSW,
    wNicheSW,
    wStatueSW,
    wKeyhole,
    wWritingSW
  ]

  SpecialWallTooltips = SpecialWalls.mapIt(($it).title())

  FloorGroup1 = @[
    fDoor,
    fLockedDoor,
    fArchway
  ]

  FloorGroup2 = @[
    fSecretDoor,
    fSecretDoorBlock,
    fOneWayDoor1,
    fOneWayDoor2
  ]

  FloorGroup3 = @[
    fPressurePlate,
    fHiddenPressurePlate
  ]

  FloorGroup4 = @[
    fClosedPit,
    fOpenPit,
    fHiddenPit,
    fCeilingPit
  ]

  FloorGroup5 = @[
    fTeleportSource,
    fTeleportDestination,
    fSpinner,
    fInvisibleBarrier
  ]

  FloorGroup6 = @[
    fStairsDown,
    fStairsUp,
    fEntranceDoor,
    fExitDoor
  ]

  FloorGroup7 = @[
    fBridge
  ]

# }}}
# {{{ App context

type
  AppContext = ref object
    win:         CSDWindow
    vg:          NVGContext

    prefs:       Preferences
    paths:       Paths

    doc:         Document
    opts:        Options
    ui:          UIState
    dialogs:     Dialogs

    theme:       Theme
    themeEditor: ThemeEditor
    quickRef:    QuickRef
    splash:      Splash
    aboutLogo:   AboutLogo

    shouldClose: bool
    updateUI:    bool

    logFile:     File


  Preferences = object
    showSplash:         bool
    autoCloseSplash:    bool
    splashTimeoutSecs:  Natural

    loadLastMap:        bool
    vsync:              bool

    autosave*:          bool
    autosaveFreqMins:   Natural


  Paths = object
    appDir:             string
    dataDir:            string
    logDir:             string
    userDataDir:        string
    configDir:          string
    manualDir:          string
    autosaveDir:        string

    themesDir:          string
    themeImagesDir:     string
    userThemesDir:      string
    userThemeImagesDir: string

    configFile:         string
    logFile:            string


  Document = object
    filename:          string
    map:               Map
    undoManager:       UndoManager[Map, UndoStateData]
    lastAutosaveTime:  MonoTime

  Options = object
    showNotesPane:     bool
    showToolsPane:     bool

    drawTrail:         bool
    walkMode:          bool
    wasdMode:          bool

    showThemeEditor:   bool
    showQuickReference: bool


  UIState = object
    cursor:            Location
    prevCursor:        Location
    cursorOrient:      CardinalDir
    editMode:          EditMode

    prevCursorViewX:   float
    prevCursorViewY:   float

    selection:         Option[Selection]
    selRect:           Option[SelectionRect]
    copyBuf:           Option[SelectionBuffer]
    nudgeBuf:          Option[SelectionBuffer]
    cutToBuffer:       bool
    moveUndoLocation:  Location

    status:            StatusMessage

    currSpecialWall:   Natural
    currFloorColor:    Natural

    drawWallRepeatAction:    DrawWallRepeatAction
    drawWallRepeatWall:      Wall
    drawWallRepeatDirection: CardinalDir

    mouseCanStartExcavateAction: bool

    manualNoteTooltipState: ManualNoteTooltipState

    levelTopPad:       float
    levelRightPad:     float
    levelBottomPad:    float
    levelLeftPad:      float

    linkSrcLocation:   Location

    drawLevelParams:   DrawLevelParams
    toolbarDrawParams: DrawLevelParams

    levelDrawAreaWidth:  float
    levelDrawAreaHeight: float

    backgroundImage:   Option[Paint]


  ManualNoteTooltipState = object
    show:     bool
    location: Location
    mx:       float
    my:       float

  StatusMessage = object
    icon:           string
    message:        string
    commands:       seq[string]
    warning:        string
    warningT0:      MonoTime
    warningTimeout: Duration

    keepMessageAfterWarningExpired:  bool


  EditMode = enum
    emNormal,
    emColorFloor,
    emDrawClearFloor,
    emDrawSpecialWall,
    emDrawSpecialWallRepeat,
    emDrawWall,
    emDrawWallRepeat,
    emEraseCell,
    emEraseTrail,
    emExcavateTunnel,
    emMovePreview,
    emNudgePreview,
    emPastePreview,
    emSelect,
    emSelectDraw,
    emSelectErase,
    emSelectRect,
    emSetCellLink

  DrawWallRepeatAction = enum
    dwaNone  = (0, "none"),
    dwaSet   = (1, "set"),
    dwaClear = (2, "clear")

  Theme = object
    config:                 HoconNode
    prevConfig:             HoconNode

    themeNames:             seq[ThemeName]
    currThemeIndex:         Natural
    nextThemeIndex:         Option[Natural]
    hideThemeLoadedMessage: bool
    themeReloaded:          bool
    updateThemeStyles:      bool
    loadBackgroundImage:    bool

    buttonStyle:            ButtonStyle
    checkBoxStyle:          CheckboxStyle
    dialogStyle:            koi.DialogStyle
    labelStyle:             LabelStyle
    radioButtonStyle:       RadioButtonsStyle
    textAreaStyle:          TextAreaStyle
    textFieldStyle:         koi.TextFieldStyle

    aboutDialogStyle:       koi.DialogStyle
    aboutButtonStyle:       ButtonStyle

    iconRadioButtonsStyle:  RadioButtonsStyle
    warningLabelStyle:      LabelStyle
    errorLabelStyle:        LabelStyle

    levelDropDownStyle:     DropDownStyle
    noteTextAreaStyle:      TextAreaStyle

    windowStyle:            WindowStyle
    statusBarStyle:         StatusBarStyle
    notesPaneStyle:         NotesPaneStyle
    toolbarPaneStyle:       ToolbarPaneStyle
    levelStyle:             LevelStyle


  ThemeName = object
    name:      string
    userTheme: bool
    override:  bool

  Dialog = enum
    dlgNone,

    dlgAboutDialog,
    dlgPreferencesDialog,

    dlgSaveDiscardMapDialog,

    dlgNewMapDialog,
    dlgEditMapPropsDialog,

    dlgNewLevelDialog,
    dlgEditLevelPropsDialog,
    dlgResizeLevelDialog,
    dlgDeleteLevelDialog,

    dlgEditNoteDialog,
    dlgEditLabelDialog,

    dlgEditRegionPropsDialog,

    dlgSaveDiscardThemeDialog,
    dlgCopyThemeDialog,
    dlgRenameThemeDialog,
    dlgOverwriteThemeDialog,
    dlgDeleteThemeDialog


  Dialogs = object
    activeDialog:           Dialog

    aboutDialog:            AboutDialogParams
    preferencesDialog:      PreferencesDialogParams

    saveDiscardMapDialog:   SaveDiscardMapDialogParams

    newMapDialog:           NewMapDialogParams
    editMapPropsDialog:     EditMapPropsDialogParams

    newLevelDialog:         LevelPropertiesDialogParams
    editLevelPropsDialog:   LevelPropertiesDialogParams
    resizeLevelDialog:      ResizeLevelDialogParams

    editNoteDialog:         EditNoteDialogParams
    editLabelDialog:        EditLabelDialogParams

    editRegionPropsDialog:  EditRegionPropsParams

    saveDiscardThemeDialog: SaveDiscardThemeDialogParams
    copyThemeDialog:        CopyThemeDialogParams
    renameThemeDialog:      RenameThemeDialogParams
    overwriteThemeDialog:   OverwriteThemeDialogParams


  AboutDialogParams = object
    logoPaint:    Paint
    outlinePaint: Paint
    shadowPaint:  Paint


  PreferencesDialogParams = object
    activeTab:          Natural
    activateFirstTextField: bool

    showSplash:         bool
    autoCloseSplash:    bool
    splashTimeoutSecs:  string
    loadLastMap:        bool
    vsync:              bool
    autosave:           bool
    autosaveFreqMins:   string


  SaveDiscardMapDialogParams = object
    action:       proc (a: var AppContext)


  NewMapDialogParams = object
    activeTab:    Natural
    activateFirstTextField: bool

    title:        string
    game:         string
    author:       string

    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  EditMapPropsDialogParams = object
    activeTab:    Natural
    activateFirstTextField: bool

    title:        string
    game:         string
    author:       string

    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  LevelPropertiesDialogParams = object
    activeTab:         Natural
    activateFirstTextField: bool

    # General tab
    locationName:      string
    levelName:         string
    elevation:         string
    rows:              string
    cols:              string

    # Coordinates tab
    overrideCoordOpts: bool
    origin:            Natural
    rowStyle:          Natural
    columnStyle:       Natural
    rowStart:          string
    columnStart:       string

    # Regions tab
    enableRegions:     bool
    colsPerRegion:     string
    rowsPerRegion:     string
    perRegionCoords:   bool

    # Notes tab
    notes:              string


  ResizeLevelDialogParams = object
    activateFirstTextField: bool

    rows:         string
    cols:         string
    anchor:       ResizeAnchor


  ResizeAnchor = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


  EditNoteDialogParams = object
    activateFirstTextField: bool
    editMode:     bool
    row:          Natural
    col:          Natural
    kind:         AnnotationKind
    index:        Natural
    indexColor:   Natural
    customId:     string
    icon:         Natural
    text:         string


  EditLabelDialogParams = object
    activateFirstTextField: bool
    editMode:     bool
    row:          Natural
    col:          Natural
    text:         string
    color:        Natural


  EditRegionPropsParams = object
    activateFirstTextField: bool
    name:         string
    notes:        string

  SaveDiscardThemeDialogParams = object
    action:       proc (a: var AppContext)

  CopyThemeDialogParams = object
    activateFirstTextField: bool
    newThemeName: string

  RenameThemeDialogParams = object
    activateFirstTextField: bool
    newThemeName: string


  OverwriteThemeDialogParams = object
    themeName:    string
    action:       proc (a: var AppContext)


  ThemeEditor = object
    modified:                bool

    sectionUserInterface:    bool
    sectionWidget:           bool
    sectionTextField:        bool
    sectionDialog:           bool
    sectionTitleBar:         bool
    sectionStatusBar:        bool
    sectionLevelDropDown:    bool
    sectionAboutButton:      bool
    sectionAboutDialog:      bool
    sectionQuickHelp:        bool
    sectionSplashImage:      bool

    sectionLevel:            bool
    sectionLevelGeneral:     bool
    sectionGrid:             bool
    sectionOutline:          bool
    sectionShadow:           bool
    sectionBackgroundHatch:  bool
    sectionFloorColors:      bool
    sectionNotes:            bool
    sectionLabels:           bool

    sectionPanes:            bool
    sectionNotesPane:        bool
    sectionToolbarPane:      bool


  QuickRef = object
    activeTab:    Natural


  Splash = object
    win:           Window
    vg:            NVGContext
    show:          bool
    t0:            MonoTime

    logo:          ImageData
    outline:       ImageData
    shadow:        ImageData

    logoImage:     Image
    outlineImage:  Image
    shadowImage:   Image

    logoPaint:     Paint
    outlinePaint:  Paint
    shadowPaint:   Paint

    updateLogoImage:     bool
    updateOutlineImage:  bool
    updateShadowImage:   bool


  AboutLogo = object
    logo:             ImageData
    logoImage:        Image
    logoPaint:        Paint
    updateLogoImage:  bool


var g_app: AppContext

using a: var AppContext

# }}}
# {{{ Keyboard shortcuts

type MoveKeys = object
  left, right, up, down: set[Key]

const
  MoveKeysCursor = MoveKeys(
    left  : {keyLeft,     keyH, keyKp4},
    right : {keyRight,    keyL, keyKp6},
    up    : {keyUp,       keyK, keyKp8},
    down  : {Key.keyDown, keyJ, keyKp2, keyKp5}
  )

  MoveKeysWasd = MoveKeys(
    left  : MoveKeysCursor.left  + {keyA},
    right : MoveKeysCursor.right + {keyD},
    up    : MoveKeysCursor.up    + {keyW},
    down  : MoveKeysCursor.down  + {Key.keyS}
  )


type WalkKeys = object
  forward, backward, strafeLeft, strafeRight, turnLeft, turnRight: set[Key]

const
  WalkKeysCursor = WalkKeys(
    forward     : {keyKp8, keyUp},
    backward    : {keyKp2, keyKp5, Key.keyDown},
    strafeLeft  : {keyKp4, keyLeft},
    strafeRight : {keyKp6, keyRight},
    turnLeft    : {keyKp7},
    turnRight   : {keyKp9}
  )

  WalkKeysWasd = WalkKeys(
    forward     : WalkKeysCursor.forward     + {keyW},
    backward    : WalkKeysCursor.backward    + {Key.keyS},
    strafeLeft  : WalkKeysCursor.strafeLeft  + {keyA},
    strafeRight : WalkKeysCursor.strafeRight + {keyD},
    turnLeft    : WalkKeysCursor.turnLeft    + {keyQ},
    turnRight   : WalkKeysCursor.turnRight   + {keyE}
  )

const
  AllWasdMoveKeys = {keyQ, keyW, keyE, keyA, Key.keyS, keyD}


# TODO
#[
type DiagonalKeys = object
  upLeft, upRight, downLeft, downRight: set[Key]

const
  DiagonalKeysWall = DiagonalKeys(
    upLeft    : {keyKp7, keyY},
    upRight   : {keyKp9, keyU},
    downLeft  : {keyKp1, keyB},
    downRight : {keyKp3, keyN}
  )
]#

type AppShortcut = enum
  # General
  scNextTextField,
  scAccept,
  scCancel,
  scDiscard,
  scUndo,
  scRedo,

  # Maps
  scNewMap,
  scOpenMap,
  scSaveMap,
  scSaveMapAs,
  scEditMapProps,

  # Levels
  scNewLevel,
  scDeleteLevel,
  scEditLevelProps,
  scResizeLevel,

  # Regions
  scEditRegionProps,

  # Themes
  scReloadTheme,
  scPreviousTheme,
  scNextTheme,

  # Editing
  scCycleFloorGroup1Forward,
  scCycleFloorGroup2Forward,
  scCycleFloorGroup3Forward,
  scCycleFloorGroup4Forward,
  scCycleFloorGroup5Forward,
  scCycleFloorGroup6Forward,
  scCycleFloorGroup7Forward,

  scCycleFloorGroup1Backward,
  scCycleFloorGroup2Backward,
  scCycleFloorGroup3Backward,
  scCycleFloorGroup4Backward,
  scCycleFloorGroup5Backward,
  scCycleFloorGroup6Backward,
  scCycleFloorGroup7Backward,

  scExcavateTunnel,
  scEraseCell,
  scDrawClearFloor,
  scToggleFloorOrientation,

  scSetFloorColor,
  scPickFloorColor,
  scPreviousFloorColor,
  scNextFloorColor,

  scSelectFloorColor1,
  scSelectFloorColor2,
  scSelectFloorColor3,
  scSelectFloorColor4,
  scSelectFloorColor5,
  scSelectFloorColor6,
  scSelectFloorColor7,
  scSelectFloorColor8,
  scSelectFloorColor9,
  scSelectFloorColor10,

  scDrawWall,
  scDrawWallRepeat,
  scDrawSpecialWall,
  scPreviousSpecialWall,
  scNextSpecialWall,

  scSelectSpecialWall1,
  scSelectSpecialWall2,
  scSelectSpecialWall3,
  scSelectSpecialWall4,
  scSelectSpecialWall5,
  scSelectSpecialWall6,
  scSelectSpecialWall7,
  scSelectSpecialWall8,
  scSelectSpecialWall9,
  scSelectSpecialWall10,
  scSelectSpecialWall11,
  scSelectSpecialWall12,

  scEraseTrail,
  scExcavateTrail,
  scClearTrail,

  scJumpToLinkedCell,
  scLinkCell,

  scPreviousLevel,
  scNextLevel,

  scZoomIn,
  scZoomOut,

  scMarkSelection,
  scPaste,
  scPastePreview,
  scNudgePreview,
  scPasteAccept,

  scEditNote,
  scEraseNote,
  scEditLabel,
  scEraseLabel,

  scShowNoteTooltip,

  # Select mode
  scSelectionDraw,
  scSelectionErase,
  scSelectionAll,
  scSelectionNone,
  scSelectionAddRect,
  scSelectionSubRect,
  scSelectionCopy,
  scSelectionCut,
  scSelectionMove,
  scSelectionEraseArea,
  scSelectionFillArea,
  scSelectionSurroundArea,
  scSelectionSetFloorColorArea,
  scSelectionCropArea,

  # Options
  scToggleCellCoords,
  scToggleNotesPane,
  scToggleToolsPane,
  scToggleWalkMode,
  scToggleWasdMode,
  scToggleDrawTrail,
  scToggleTitleBar,

  # Misc
  scShowAboutDialog,
  scOpenUserManual,
  scToggleThemeEditor,
  scEditPreferences,
  scToggleQuickReference,


# TODO some shortcuts win/mac specific?
# TODO introduce shortcuts for everything
let g_appShortcuts = {
  # General
  scNextTextField:      @[mkKeyShortcut(keyTab,           {})],

  scAccept:             @[mkKeyShortcut(keyEnter,         {}),
                          mkKeyShortcut(keyKpEnter,       {})],

  scCancel:             @[mkKeyShortcut(keyEscape,        {}),
                          mkKeyShortcut(keyLeftBracket,   {mkCtrl})],

  scDiscard:            @[mkKeyShortcut(keyD,             {mkAlt})],

  scUndo:               @[mkKeyShortcut(keyZ,             {mkCtrl}),
                          mkKeyShortcut(keyU,             {})],

  scRedo:               @[mkKeyShortcut(keyY,             {mkCtrl}),
                          mkKeyShortcut(keyR,             {mkCtrl})],

  # Maps
  scNewMap:             @[mkKeyShortcut(keyN,             {mkCtrl, mkAlt})],
  scOpenMap:            @[mkKeyShortcut(keyO,             {mkCtrl})],
  scSaveMap:            @[mkKeyShortcut(Key.keyS,         {mkCtrl})],
  scSaveMapAs:          @[mkKeyShortcut(Key.keyS,         {mkCtrl, mkShift})],
  scEditMapProps:       @[mkKeyShortcut(keyP,             {mkCtrl, mkAlt})],

  # Levels
  scNewLevel:           @[mkKeyShortcut(keyN,             {mkCtrl})],
  scDeleteLevel:        @[mkKeyShortcut(keyD,             {mkCtrl})],
  scEditLevelProps:     @[mkKeyShortcut(keyP,             {mkCtrl})],
  scResizeLevel:        @[mkKeyShortcut(keyE,             {mkCtrl})],

  # Regions
  scEditRegionProps:    @[mkKeyShortcut(keyR,             {mkCtrl, mkAlt})],

  # Themes
  scReloadTheme:        @[mkKeyShortcut(keyHome,          {mkCtrl})],
  scPreviousTheme:      @[mkKeyShortcut(keyPageUp,        {mkCtrl})],
  scNextTheme:          @[mkKeyShortcut(keyPageDown,      {mkCtrl})],

  # Editing
  scCycleFloorGroup1Forward:   @[mkKeyShortcut(key1,      {})],
  scCycleFloorGroup2Forward:   @[mkKeyShortcut(key2,      {})],
  scCycleFloorGroup3Forward:   @[mkKeyShortcut(key3,      {})],
  scCycleFloorGroup4Forward:   @[mkKeyShortcut(key4,      {})],
  scCycleFloorGroup5Forward:   @[mkKeyShortcut(key5,      {})],
  scCycleFloorGroup6Forward:   @[mkKeyShortcut(key6,      {})],
  scCycleFloorGroup7Forward:   @[mkKeyShortcut(key7,      {})],

  scCycleFloorGroup1Backward:  @[mkKeyShortcut(key1,      {mkShift})],
  scCycleFloorGroup2Backward:  @[mkKeyShortcut(key2,      {mkShift})],
  scCycleFloorGroup3Backward:  @[mkKeyShortcut(key3,      {mkShift})],
  scCycleFloorGroup4Backward:  @[mkKeyShortcut(key4,      {mkShift})],
  scCycleFloorGroup5Backward:  @[mkKeyShortcut(key5,      {mkShift})],
  scCycleFloorGroup6Backward:  @[mkKeyShortcut(key6,      {mkShift})],
  scCycleFloorGroup7Backward:  @[mkKeyShortcut(key7,      {mkShift})],

  scExcavateTunnel:            @[mkKeyShortcut(keyD,      {})],
  scEraseCell:                 @[mkKeyShortcut(keyE,      {})],
  scDrawClearFloor:            @[mkKeyShortcut(keyF,      {})],
  scToggleFloorOrientation:    @[mkKeyShortcut(keyO,      {})],

  scSetFloorColor:             @[mkKeyShortcut(keyC,      {})],
  scPickFloorColor:            @[mkKeyShortcut(keyI,      {})],
  scPreviousFloorColor:        @[mkKeyShortcut(keyComma,  {})],
  scNextFloorColor:            @[mkKeyShortcut(keyPeriod, {})],

  scSelectFloorColor1:         @[mkKeyShortcut(key1,      {mkCtrl})],
  scSelectFloorColor2:         @[mkKeyShortcut(key2,      {mkCtrl})],
  scSelectFloorColor3:         @[mkKeyShortcut(key3,      {mkCtrl})],
  scSelectFloorColor4:         @[mkKeyShortcut(key4,      {mkCtrl})],
  scSelectFloorColor5:         @[mkKeyShortcut(key5,      {mkCtrl})],
  scSelectFloorColor6:         @[mkKeyShortcut(key6,      {mkCtrl})],
  scSelectFloorColor7:         @[mkKeyShortcut(key7,      {mkCtrl})],
  scSelectFloorColor8:         @[mkKeyShortcut(key8,      {mkCtrl})],
  scSelectFloorColor9:         @[mkKeyShortcut(key9,      {mkCtrl})],
  scSelectFloorColor10:        @[mkKeyShortcut(key0,      {mkCtrl})],

  scDrawWall:                  @[mkKeyShortcut(keyW,      {})],
  scDrawSpecialWall:           @[mkKeyShortcut(keyR,      {})],

  scDrawWallRepeat:            @[mkKeyShortcut(keyLeftShift,  {mkShift}),
                                 mkKeyShortcut(keyRightShift, {mkShift})],

  scPreviousSpecialWall:       @[mkKeyShortcut(keyLeftBracket,  {})],
  scNextSpecialWall:           @[mkKeyShortcut(keyRightBracket, {})],

  scSelectSpecialWall1:        @[mkKeyShortcut(key1,      {mkAlt})],
  scSelectSpecialWall2:        @[mkKeyShortcut(key2,      {mkAlt})],
  scSelectSpecialWall3:        @[mkKeyShortcut(key3,      {mkAlt})],
  scSelectSpecialWall4:        @[mkKeyShortcut(key4,      {mkAlt})],
  scSelectSpecialWall5:        @[mkKeyShortcut(key5,      {mkAlt})],
  scSelectSpecialWall6:        @[mkKeyShortcut(key6,      {mkAlt})],
  scSelectSpecialWall7:        @[mkKeyShortcut(key7,      {mkAlt})],
  scSelectSpecialWall8:        @[mkKeyShortcut(key8,      {mkAlt})],
  scSelectSpecialWall9:        @[mkKeyShortcut(key9,      {mkAlt})],
  scSelectSpecialWall10:       @[mkKeyShortcut(key0,      {mkAlt})],
  scSelectSpecialWall11:       @[mkKeyShortcut(keyMinus,  {mkAlt})],
  scSelectSpecialWall12:       @[mkKeyShortcut(keyEqual,  {mkAlt})],

  scEraseTrail:                @[mkKeyShortcut(keyX,      {})],
  scExcavateTrail:             @[mkKeyShortcut(keyD,      {mkCtrl, mkAlt})],
  scClearTrail:                @[mkKeyShortcut(keyX,      {mkCtrl, mkAlt})],

  scJumpToLinkedCell:          @[mkKeyShortcut(keyG,      {})],
  scLinkCell:                  @[mkKeyShortcut(keyG,      {mkShift})],

  scPreviousLevel:             @[mkKeyShortcut(keyPageUp,     {}),
                                 mkKeyShortcut(keyKpSubtract, {}),
                                 mkKeyShortcut(keyMinus,      {mkCtrl})],

  scNextLevel:                 @[mkKeyShortcut(keyPageDown,   {}),
                                 mkKeyShortcut(keyKpAdd,      {}),
                                 mkKeyShortcut(keyEqual,      {mkCtrl})],

  scZoomIn:                    @[mkKeyShortcut(keyEqual,      {})],
  scZoomOut:                   @[mkKeyShortcut(keyMinus,      {})],

  scMarkSelection:             @[mkKeyShortcut(keyM,          {})],
  scPaste:                     @[mkKeyShortcut(keyP,          {})],
  scPastePreview:              @[mkKeyShortcut(keyP,          {mkShift})],
  scNudgePreview:              @[mkKeyShortcut(keyG,          {mkCtrl})],

  scPasteAccept:               @[mkKeyShortcut(keyP,          {}),
                                 mkKeyShortcut(keyEnter,      {}),
                                 mkKeyShortcut(keyKpEnter,    {})],

  scEditNote:                  @[mkKeyShortcut(keyN,          {})],
  scEraseNote:                 @[mkKeyShortcut(keyN,          {mkShift})],
  scEditLabel:                 @[mkKeyShortcut(keyT,          {mkCtrl})],
  scEraseLabel:                @[mkKeyShortcut(keyT,          {mkShift})],

  scShowNoteTooltip:           @[mkKeyShortcut(keySpace,      {})],

  # Select mode
  scSelectionDraw:               @[mkKeyShortcut(keyD,        {})],
  scSelectionErase:              @[mkKeyShortcut(keyE,        {})],
  scSelectionAll:                @[mkKeyShortcut(keyA,        {})],
  scSelectionNone:               @[mkKeyShortcut(keyU,        {})],
  scSelectionAddRect:            @[mkKeyShortcut(keyR,        {})],
  scSelectionSubRect:            @[mkKeyShortcut(Key.keyS,    {})],

  scSelectionCopy:               @[mkKeyShortcut(keyC,        {}),
                                   mkKeyShortcut(keyY,        {})],

  scSelectionCut:                @[mkKeyShortcut(keyX,        {})],
  scSelectionMove:               @[mkKeyShortcut(keyM,        {mkCtrl})],
  scSelectionEraseArea:          @[mkKeyShortcut(keyE,        {mkCtrl})],
  scSelectionFillArea:           @[mkKeyShortcut(keyF,        {mkCtrl})],
  scSelectionSurroundArea:       @[mkKeyShortcut(Key.keyS,    {mkCtrl})],
  scSelectionSetFloorColorArea:  @[mkKeyShortcut(keyC,        {mkCtrl})],
  scSelectionCropArea:           @[mkKeyShortcut(keyR,        {mkCtrl})],

  # Options
  scToggleCellCoords:   @[mkKeyShortcut(keyC,             {mkAlt})],
  scToggleNotesPane:    @[mkKeyShortcut(keyN,             {mkAlt})],
  scToggleToolsPane:    @[mkKeyShortcut(keyT,             {mkAlt})],
  scToggleWalkMode:     @[mkKeyShortcut(keyGraveAccent,   {})],
  scToggleWasdMode:     @[mkKeyShortcut(keyTab,           {})],
  scToggleDrawTrail:    @[mkKeyShortcut(keyT,             {})],
  scToggleTitleBar:     @[mkKeyShortcut(keyT,             {mkAlt, mkShift})],

  # Misc
  scShowAboutDialog:      @[mkKeyShortcut(keyA,           {mkCtrl})],
  scOpenUserManual:       @[mkKeyShortcut(keyF1,          {})],
  scToggleThemeEditor:    @[mkKeyShortcut(keyF12,         {})],
  scEditPreferences:      @[mkKeyShortcut(keyU,           {mkCtrl, mkAlt})],
  scToggleQuickReference: @[mkKeyShortcut(keySlash,       {mkShift})]

}.toTable

# {{{ toStr()
proc toStr(k: Key): string =
  case k
  of key0..key9: $k
  of keyA..keyZ, keyF1..keyF25: ($k).toUpper()
  of keyUnknown: "???"
  of keySpace: "Space"
  of keyApostrophe: "'"
  of keyComma: ","
  of keyMinus: "-"
  of keyPeriod: "."
  of keySlash: "/"
  of keySemicolon: ";"
  of keyEqual: "="
  of keyLeftBracket: "["
  of keyBackslash: "\\"
  of keyRightBracket: "]"
  of keyGraveAccent: "`"

  of keyWorld1: "World1"
  of keyWorld2: "World2"
  of keyEscape: "Esc"
  of keyEnter: "Enter"
  of keyTab: "Tab"
  of keyBackspace: "Bksp"
  of keyInsert: "Ins"
  of keyDelete: "Del"
  of keyRight: "Right"
  of keyLeft: "Left"
  of keyDown: "Down"
  of keyUp: "Up"

  of keyPageUp: "PgUp"
  of keyPageDown: "PgDn"
  of keyHome: "Home"
  of keyEnd: "End"
  of keyCapsLock: "CapsLock"
  of keyScrollLock: "ScrollLock"
  of keyNumLock: "NumLock"
  of keyPrintScreen: "PrtSc"
  of keyPause: "Pause"

  of keyKp0: "kp0"
  of keyKp1: "kp1"
  of keyKp2: "kp2"
  of keyKp3: "kp3"
  of keyKp4: "kp4"
  of keyKp5: "kp5"
  of keyKp6: "kp6"
  of keyKp7: "kp7"
  of keyKp8: "kp8"
  of keyKp9: "kp9"
  of keyKpDecimal: "kp."
  of keyKpDivide: "kp/"
  of keyKpMultiply: "kp*"
  of keyKpSubtract: "kp-"
  of keyKpAdd: "kp+"
  of keyKpEnter: "kpEnter"
  of keyKpEqual: "kp="

  of keyLeftShift: "LShift"
  of keyLeftControl: "LCtrl"
  of keyLeftAlt: "LAlt"
  of keyLeftSuper: "LSuper"
  of keyRightShift: "RShift"
  of keyRightControl: "RCtrl"
  of keyRightAlt: "RAlt"
  of keyRightSuper: "RSuper"
  of keyMenu: "Menu"


proc toStr(k: KeyShortcut): string =
  var s: seq[string] = @[]
  if mkCtrl  in k.mods: s.add("Ctrl")
  if mkShift in k.mods: s.add("Shift")
  if mkAlt   in k.mods: s.add("Alt")
  s.add(k.key.toStr())
  s.join("+")


proc toStr(sc: AppShortcut, idx = -1): string =

  var s: seq[string] = @[]
  if idx == -1:
    for k in g_appShortcuts[sc]:
      s.add(k.toStr())
    result = s.join("/")
  else:
    result = g_appShortcuts[sc][idx].toStr()
# }}}

# }}}

# {{{ Logging

# {{{ rollLogFile(a)
proc rollLogFile(a) =
  alias(p, a.paths)

  let fileNames = @[
    p.logFile & ".bak3",
    p.logFile & ".bak2",
    p.logFile & ".bak1",
    p.logFile
  ]

  for i, fname in fileNames:
    if fileExists(fname):
      if i == 0:
        discard tryRemoveFile(fname)
      else:
        try:
          moveFile(fname, fileNames[i-1])
        except CatchableError:
          discard

# }}}
# {{{ initLogger(a)
proc initLogger(a) =
  rollLogFile(a)
  a.logFile = open(a.paths.logFile, fmWrite)

  var fileLog = newFileLogger(
    a.logFile,
    fmtStr = "[$levelname] $date $time - ",
    levelThreshold = if defined(DEBUG): lvlDebug else: lvlInfo
  )

  addHandler(fileLog)

# }}}
# {{{ logError()
proc logError(e: ref Exception, msgPrefix: string = "") =
  var msg = "Error message: " & e.msg & "\n\nStack trace:\n" & getStackTrace(e)
  if msgPrefix != "":
    msg = msgPrefix & "\n" & msg

  logging.error(msg)

# }}}

# }}}

# {{{ UI helpers

# {{{ viewRow()
func viewRow(row: Natural; a): int =
  row - a.ui.drawLevelParams.viewStartRow

func viewRow(a): int =
  viewRow(a.ui.cursor.row, a)

# }}}
# {{{ viewCol()
proc viewCol(col: Natural; a): int =
  col - a.ui.drawLevelParams.viewStartCol

func viewCol(a): int =
  viewCol(a.ui.cursor.col, a)

# }}}
# {{{ currSortedLevelIdx()
func currSortedLevelIdx(a): Natural =
  a.doc.map.findSortedLevelIdxByLevelIdx(a.ui.cursor.level)

# }}}
# {{{ currLevel()
func currLevel(a): common.Level =
  a.doc.map.levels[a.ui.cursor.level]

# }}}
# {{{ currRegion()
func currRegion(a): Option[Region] =
  let l = currLevel(a)
  if l.regionOpts.enabled:
    let rc = a.doc.map.getRegionCoords(a.ui.cursor)
    l.getRegion(rc)
  else:
    Region.none

# }}}
# {{{ coordOptsForCurrLevel()
func coordOptsForCurrLevel(a): CoordinateOptions =
  a.doc.map.coordOptsForLevel(a.ui.cursor.level)

# }}}

# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string]; a) =
  alias(s, a.ui.status)

  s.icon = icon
  s.message = msg
  s.warning = ""
  s.commands = commands


proc setStatusMessage(icon, msg: string; a) =
  setStatusMessage(icon, msg, commands = @[], a)

proc setStatusMessage(msg: string; a) =
  setStatusMessage(NoIcon, msg, commands = @[], a)

# }}}
# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  setStatusMessage(NoIcon, msg = "", commands = @[], a)

# }}}
# {{{ setWarningMessage()
proc setWarningMessage(msg: string, keepStatusMessage = false,
                       autohide = true; a) =
  alias(s, a.ui.status)

  s.warning = msg
  s.warningT0 = getMonoTime()
  s.warningTimeout = if autohide: WarningMessageTimeout else: InfiniteDuration
  s.keepMessageAfterWarningExpired = keepStatusMessage

# }}}
# {{{ setSelectModeSelectMessage()
proc setSelectModeSelectMessage(a) =
  setStatusMessage(
    IconSelection, "Mark selection",
    @[scSelectionDraw.toStr(),    "draw",
      scSelectionErase.toStr(),   "erase",
      scSelectionAddRect.toStr(), "add rect",
      scSelectionSubRect.toStr(), "sub rect",
      scSelectionAll.toStr(),     "mark all",
      scSelectionNone.toStr(),    "unmark all",
      scSelectionCopy.toStr(),    "copy",
      scSelectionCut.toStr(),     "cut",
      "Ctrl",                     "special"],
    a
  )

# }}}
# {{{ setSelectModeActionMessage()
proc setSelectModeActionMessage(a) =
  setStatusMessage(
    IconSelection, "Mark selection",
    @[scSelectionEraseArea.toStr(),         "erase",
      scSelectionFillArea.toStr(),          "fill",
      scSelectionSurroundArea.toStr(),      "surround",
      scSelectionCropArea.toStr(),          "crop",
      scSelectionMove.toStr(),              "move",
      scSelectionSetFloorColorArea.toStr(), "set colour"],
    a
  )

# }}}
# {{{ setSetLinkDestinationMessage()
proc setSetLinkDestinationMessage(floor: Floor; a) =
  setStatusMessage(IconLink,
                   fmt"Set {linkFloorToString(floor)} destination",
                   @[IconArrowsAll, "select cell",
                   scAccept.toStr(0), "set", scCancel.toStr(0), "cancel"], a)
# }}}

# {{{ drawAreaWidth()
proc drawAreaWidth(a): float =
  if a.opts.showThemeEditor: koi.winWidth() - ThemePaneWidth
  else: koi.winWidth()

# }}}
# {{{ drawAreaHeight()
proc drawAreaHeight(a): float =
  koi.winHeight() - a.win.titleBarHeight

# }}}
# {{{ toolsPaneWidth()
proc toolsPaneWidth(a): float =
  if drawAreaHeight(a) < ToolsPaneYBreakpoint2: ToolsPaneWidthWide
  else: ToolsPaneWidthNarrow

# }}}

# {{{ setCursor()
proc setCursor(cur: Location; a) =
  with a:
    if cur.level != ui.prevCursor.level:
      opts.drawTrail = false

    if opts.drawTrail and cur != ui.prevCursor:
      actions.drawTrail(doc.map, loc=cur, undoLoc=ui.prevCursor,
                        doc.undoManager)
    ui.cursor = cur

# }}}
# {{{ stepCursor()
proc stepCursor(cur: Location, dir: CardinalDir, steps: Natural; a): Location =
  alias(dp, a.ui.drawLevelParams)

  let l = a.doc.map.levels[cur.level]
  let sm = ScrollMargin
  var cur = cur

  case dir:
  of dirE:
    cur.col = min(cur.col + steps, l.cols-1)
    let viewCol = viewCol(cur.col, a)
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol +
                                                        (viewCol - viewColMax))

  of dirS:
    cur.row = min(cur.row + steps, l.rows-1)
    let viewRow = viewRow(cur.row, a)
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow +
                                                        (viewRow - viewRowMax))

  of dirW:
    cur.col = max(cur.col - steps, 0)
    let viewCol = viewCol(cur.col, a)
    if viewCol < sm:
      dp.viewStartCol = max(dp.viewStartCol - (sm - viewCol), 0)

  of dirN:
    cur.row = max(cur.row - steps, 0)
    let viewRow = viewRow(cur.row, a)
    if viewRow < sm:
      dp.viewStartRow = max(dp.viewStartRow - (sm - viewRow), 0)

  result = cur

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, steps: Natural = 1; a) =
  let cur = stepCursor(a.ui.cursor, dir, steps, a)
  setCursor(cur, a)

# }}}
# {{{ moveCursorTo()
proc moveCursorTo(loc: Location; a) =
  var cur = a.ui.cursor
  cur.level = loc.level

  let dx = loc.col - cur.col
  let dy = loc.row - cur.row

  cur = if   dx < 0: stepCursor(cur, dirW, -dx, a)
        elif dx > 0: stepCursor(cur, dirE,  dx, a)
        else: cur

  cur = if   dy < 0: stepCursor(cur, dirN, -dy, a)
        elif dy > 0: stepCursor(cur, dirS,  dy, a)
        else: cur

  setCursor(cur, a)

# }}}
# {{{ centerCursorAt()
proc centerCursorAt(loc: Location; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)

  dp.viewStartRow = (loc.row.int - dp.viewRows div 2).clamp(0, l.rows-1)
  dp.viewStartCol = (loc.col.int - dp.viewCols div 2).clamp(0, l.cols-1)

  moveCursorTo(loc, a)

# }}}
# {{{ locationAtMouse()
proc locationAtMouse(a): Option[Location] =
  alias(dp, a.ui.drawLevelParams)

  let
    mouseViewRow = ((koi.my() - dp.startY) / dp.gridSize).int
    mouseViewCol = ((koi.mx() - dp.startX) / dp.gridSize).int

    mouseRow = dp.viewStartRow + mouseViewRow
    mouseCol = dp.viewStartCol + mouseViewCol

  if mouseViewRow >= 0 and mouseRow < dp.viewStartRow + dp.viewRows and
     mouseViewCol >= 0 and mouseCol < dp.viewStartCol + dp.viewCols:

    result = Location(
      level: a.ui.cursor.level,
      row: mouseRow,
      col: mouseCol
    ).some
  else:
    result = Location.none

# }}}
# {{{ moveLevel()
proc moveLevel(dir: CardinalDir, steps: Natural = 1; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)
  let maxViewStartRow = max(l.rows - dp.viewRows, 0)
  let maxViewStartCol = max(l.cols - dp.viewCols, 0)

  var newViewStartCol = dp.viewStartCol
  var newViewStartRow = dp.viewStartRow

  case dir:
  of dirE: newViewStartCol = min(dp.viewStartCol + steps, maxViewStartCol)
  of dirW: newViewStartCol = max(dp.viewStartCol - steps, 0)
  of dirS: newViewStartRow = min(dp.viewStartRow + steps, maxViewStartRow)
  of dirN: newViewStartRow = max(dp.viewStartRow - steps, 0)

  var cur = a.ui.cursor
  cur.row = cur.row + viewRow(newViewStartRow, a)
  cur.col = cur.col + viewCol(newViewStartCol, a)

  setCursor(cur, a)

  dp.viewStartRow = newViewStartRow
  dp.viewStartCol = newViewStartCol

# }}}

# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  with a.ui.cursor:
    level = 0
    row = 0
    col = 0

  with a.ui.drawLevelParams:
    viewStartRow = 0
    viewStartCol = 0

# }}}
# {{{ updateLastCursorViewCoords()
proc updateLastCursorViewCoords(a) =
  alias(dp, a.ui.drawLevelParams)

  a.ui.prevCursorViewX = dp.gridSize * viewCol(a)
  a.ui.prevCursorViewY = dp.gridSize * viewRow(a)

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)

  let l = currLevel(a)

  if dp.drawCellCoords:
    a.ui.levelTopPad    = LevelTopPad_Coords
    a.ui.levelRightPad  = LevelRightPad_Coords
    a.ui.levelBottomPad = LevelBottomPad_Coords
    a.ui.levelLeftPad   = LevelLeftPad_Coords
  else:
    a.ui.levelTopPad    = LevelTopPad_NoCoords
    a.ui.levelRightPad  = LevelRightPad_NoCoords
    a.ui.levelBottomPad = LevelBottomPad_NoCoords
    a.ui.levelLeftPad   = LevelLeftPad_NoCoords

  if l.regionOpts.enabled:
    a.ui.levelTopPad += LevelTopPad_Regions

  dp.startX = ui.levelLeftPad
  dp.startY = a.win.titleBarHeight + ui.levelTopPad

  ui.levelDrawAreaWidth = drawAreaWidth(a) - a.ui.levelLeftPad -
                                             a.ui.levelRightPad

  ui.levelDrawAreaHeight = drawAreaHeight(a) - a.ui.levelTopPad -
                                               a.ui.levelBottomPad -
                                               StatusBarHeight

  if a.opts.showNotesPane:
   ui.levelDrawAreaHeight -= NotesPaneTopPad + NotesPaneHeight +
                             NotesPaneBottomPad

  if a.opts.showToolsPane:
    ui.levelDrawAreaWidth -= toolsPaneWidth(a)

  dp.viewRows = min(dp.numDisplayableRows(ui.levelDrawAreaHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(ui.levelDrawAreaWidth), l.cols)

  dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow)
  dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  let cur = a.ui.cursor
  let newCur = Location(
    level: cur.level,
    col:   viewEndCol.clamp(dp.viewStartCol, cur.col),
    row:   viewEndRow.clamp(dp.viewStartRow, cur.row)
  )

  if newCur != cur:
    setCursor(newCur, a)

  updateLastCursorViewCoords(a)

# }}}

# {{{ enterSelectMode()
proc enterSelectMode(a) =
  let l = currLevel(a)

  a.opts.drawTrail = false
  a.ui.editMode = emSelect
  a.ui.selection = some(newSelection(l.rows, l.cols))
  a.ui.drawLevelParams.drawCursorGuides = true
  setSelectModeSelectMessage(a)

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.ui.editMode = emNormal
  a.ui.selection = Selection.none
  a.ui.drawLevelParams.drawCursorGuides = false
  clearStatusMessage(a)

# }}}
# {{{ copySelection()
proc copySelection(buf: var Option[SelectionBuffer]; a): Option[Rect[Natural]] =
  alias(ui, a.ui)

  let sel = ui.selection.get
  let bbox = sel.boundingBox()

  if bbox.isSome:
    let bbox = bbox.get

    buf = some(SelectionBuffer(
      selection: newSelectionFrom(sel, bbox),
      level: newLevelFrom(currLevel(a), bbox)
    ))

    ui.cutToBuffer = false

  result = bbox

# }}}
# {{{ moveSelStart()
proc moveSelStart(dir: CardinalDir; a) =
  alias(dp, a.ui.drawLevelParams)

  let cols = a.ui.nudgeBuf.get.level.cols
  let rows = a.ui.nudgeBuf.get.level.cols

  case dir:
  of dirE:
    if dp.selStartCol < cols-1: inc(dp.selStartCol)

  of dirS:
    if dp.selStartRow < rows-1: inc(dp.selStartRow)

  of dirW:
    if dp.selStartCol + cols > 1: dec(dp.selStartCol)

  of dirN:
    if dp.selStartRow + rows > 1: dec(dp.selStartRow)

# }}}

# {{{ exitMovePreviewMode()
#
proc undoAction(a)

proc exitMovePreviewMode(a) =
  undoAction(a)
  a.doc.undoManager.truncateUndoState()
  a.ui.editMode = emNormal
  clearStatusMessage(a)

# }}}
# {{{ exitNudgePreviewMode()
proc exitNudgePreviewMode(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)

  let cur = a.ui.cursor

  ui.editMode = emNormal
  map.levels[cur.level] = ui.nudgeBuf.get.level
  ui.nudgeBuf = SelectionBuffer.none
  clearStatusMessage(a)

# }}}
# {{{ returnToNormalMode()
when defined(windows):

  proc returnToNormalMode(a) =
    alias(ui, a.ui)

    case ui.editMode
    of emNormal: discard

    of emMovePreview:
      exitMovePreviewMode(a)

    of emNudgePreview:
      exitNudgePreviewMode(a)

    of emSelect, emSelectDraw, emSelectErase, emSelectRect:
      exitSelectMode(a)

    else:
      ui.editMode = emNormal
      clearStatusMessage(a)

# }}}

# }}}
# {{{ Graphics helpers

# {{{ createImage()
template createImage(d: var ImageData): Image =
  vg.createImageRGBA(
    d.width, d.height,
    data = toOpenArray(d.data, 0, d.size()-1)
  )

# }}}
# {{{ createPattern()
proc createPattern(vg: NVGContext, img: var Image, alpha: float = 1.0,
                   xoffs: float = 0, yoffs: float = 0,
                   scale: float = 1.0): Paint =

  let (w, h) = vg.imageSize(img)
  vg.imagePattern(
    ox=xoffs, oy=yoffs, ex=w*scale, ey=h*scale, angle=0, img, alpha
  )

# }}}
# {{{ createAlpha()
proc createAlpha(d: var ImageData) =
  for i in 0..<(d.width * d.height):
    # copy the R component to the alpha channel
    d.data[i*4+3] = d.data[i*4]

# }}}
# {{{ colorImage()
func colorImage(d: var ImageData, color: Color) =
  for i in 0..<(d.width * d.height):
    d.data[i*4]   = (color.r * 255).byte
    d.data[i*4+1] = (color.g * 255).byte
    d.data[i*4+2] = (color.b * 255).byte

# }}}
# {{{ loadImage()
proc loadImage(path: string; a): Option[Paint] =
  alias(vg, a.vg)
  try:
    var img = vg.createImage(path, {ifRepeatX, ifRepeatY})
    let paint = vg.createPattern(img, scale=0.5)
    result = paint.some

  except NVGError:
    result = Paint.none

# }}}

# {{{ setSwapInterval()
proc setSwapInterval(a) =
  glfw.swapInterval(if a.prefs.vsync: 1 else: 0)

# }}}

# }}}
# {{{ Key event helpers

# {{{ hasKeyEvent()
proc hasKeyEvent(): bool =
  koi.hasEvent() and koi.currEvent().kind == ekKey

# }}}
# {{{ isKeyDown()
proc isKeyDown(ev: Event, keys: set[Key], mods: set[ModifierKey] = {},
               repeat=false): bool =

  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}

  let numKey = ev.key in keyKp0..keyKpEqual
  let eventMods = if numKey: ev.mods - {mkCapsLock}
                  else:      ev.mods - {mkCapsLock, mkNumLock}

  ev.action in a and ev.key in keys and eventMods == mods


proc isKeyDown(ev: Event, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ev, {key}, mods, repeat)

# }}}
# {{{ checkShortcut()
proc checkShortcut(ev: Event, shortcuts: set[AppShortcut],
                   actions: set[KeyAction], ignoreMods=false): bool =
  if ev.kind == ekKey:
    if ev.action in actions:
      let currShortcut = mkKeyShortcut(ev.key, ev.mods)
      for sc in shortcuts:
        if ignoreMods:
          for asc in g_appShortcuts[sc]:
            if asc.key == ev.key:
              return true
        else:
          if currShortcut in g_appShortcuts[sc]:
            return true

# }}}
# {{{ isShortcutDown()
proc isShortcutDown(ev: Event, shortcuts: set[AppShortcut],
                    repeat=false): bool =
  let actions = if repeat: {kaDown, kaRepeat} else: {kaDown}
  checkShortcut(ev, shortcuts, actions)

proc isShortcutDown(ev: Event, shortcut: AppShortcut, repeat=false): bool =
  isShortcutDown(ev, {shortcut}, repeat)

# }}}
# {{{ isShortcutUp()
proc isShortcutUp(ev: Event, shortcuts: set[AppShortcut]): bool =
  checkShortcut(ev, shortcuts, actions={kaUp}, ignoreMods=true)

proc isShortcutUp(ev: Event, shortcut: AppShortcut): bool =
  isShortcutUp(ev, {shortcut})

# }}}

# }}}

# {{{ Theme handling

# {{{ currThemeName()
func currThemeName(a): ThemeName =
  a.theme.themeNames[a.theme.currThemeIndex]

# }}}
# {{{ findThemeIndex()
func findThemeIndex(name: string; a): Option[Natural] =
  for i, themeName in a.theme.themeNames.mpairs:
    if themeName.name == name:
      return i.Natural.some

# }}}
# {{{ themePath()
func themePath(theme: ThemeName; a): string =
  let themeDir = if theme.userTheme: a.paths.userThemesDir
                 else: a.paths.themesDir
  themeDir / addFileExt(theme.name, ThemeExt)

# }}}
# {{{ makeUniqueThemeName()
proc makeUniqueThemeName(themeName: string; a): string =
  var basename = themeName
  var i = 1

  var s = themeName.rsplit(' ', maxsplit=1)
  if s.len == 2:
    try:
      i = parseInt(s[1])
      basename = s[0]
    except ValueError: discard

  while true:
    inc(i)
    result = fmt"{basename} {i}"
    if findThemeIndex(result, a).isNone: return

# }}}

# {{{ buildThemeList()
proc buildThemeList(a) =
  var themeNames: seq[ThemeName] = @[]

  func findThemeWithName(name: string): int =
    for i, themeName in themeNames.mpairs:
      if themeName.name == name: return i
    result = -1

  proc addThemeNames(themesDir: string, userTheme: bool) =
    for path in walkFiles(themesDir / fmt"*.{ThemeExt}"):
      let (_, name, _) = splitFile(path)
      let idx = findThemeWithName(name)
      if idx >= 0:
        themeNames.del(idx)
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: true)
        )
      else:
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: false)
        )

  addThemeNames(a.paths.themesDir, userTheme=false)
  addThemeNames(a.paths.userThemesDir, userTheme=true)

  if themeNames.len == 0:
    raise newException(IOError, "Could not find any themes, exiting")

  themeNames.sort(
    proc (a, b: ThemeName): int = cmp(a.name, b.name)
  )

  a.theme.themeNames = themeNames

# }}}
# {{{ loadTheme()
proc loadTheme(theme: ThemeName; a) =
  var path = themePath(theme, a)
  info(fmt"Loading theme '{theme.name}' from '{path}'")

  a.theme.config = loadTheme(path)
  a.logfile.flushFile()

# }}}
# {{{ saveTheme(a)
proc saveTheme(a) =
  try:
    with a.theme.themeNames[a.theme.currThemeIndex]:
      userTheme = true
      override = true

    let themePath = themePath(a.currThemeName, a)
    saveTheme(a.theme.config, themePath)
    a.themeEditor.modified = false

  except CatchableError as e:
    logError(e, "Error saving theme")
    setWarningMessage(fmt"Cannot save theme '{a.currThemeName.name}': {e.msg}",
                      a=a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ deleteTheme()
proc deleteTheme(theme: ThemeName; a): bool =
  if theme.userTheme:
    try:
      var path = themePath(theme, a)
      info(fmt"Deleting theme '{theme.name}' at '{path}'")

      removeFile(path)
      a.logfile.flushFile()
      result = true
    except CatchableError as e:
      logError(e, "Error deleting theme")
      setWarningMessage(fmt"Error deleting theme: {e.msg}", autohide=false, a=a)

# }}}
# {{{ copyTheme()
proc copyTheme(theme: ThemeName, newThemePath: string; a): bool =
  try:
    copyFileWithPermissions(themePath(a.currThemeName, a), newThemePath)
    result = true
  except CatchableError as e:
    logError(e, "Error copying theme")
    setWarningMessage(fmt"Error copying theme: {e.msg}", autohide=false, a=a)

# }}}
# {{{ renameTheme()
proc renameTheme(theme: ThemeName, newThemePath: string; a): bool =
  try:
    moveFile(themePath(a.currThemeName, a), newThemePath)
    result = true
  except CatchableError as e:
    logError(e, "Error renaming theme")
    setWarningMessage(fmt"Error renaming theme: {e.msg}", autohide=false, a=a)

# }}}

# {{{ loadThemeImage()
proc loadThemeImage(imageName: string, userTheme: bool, a): Option[Paint] =
  if userTheme:
    let imgPath = a.paths.userThemeImagesDir / imageName
    result = loadImage(imgPath, a)
    if result.isNone:
      info("Couldn't load image from user theme images directory: " &
           fmt"'{imgPath}'. Attempting default theme images directory.")

  let imgPath = a.paths.themeImagesDir / imageName
  result = loadImage(imgPath, a)
  if result.isNone:
    logging.error(
      "Couldn't load image from default theme images directory: '{imgPath}'"
    )

# }}}
# {{{ loadBackgroundImage()
proc loadBackgroundImage(theme: ThemeName; a) =
  let bgImageName = a.theme.windowStyle.backgroundImage

  if bgImageName != "":
    a.ui.backgroundImage = loadThemeImage(bgImageName, theme.userTheme, a)
    a.ui.drawLevelParams.backgroundImage = a.ui.backgroundImage
  else:
    a.ui.backgroundImage = Paint.none
    a.ui.drawLevelParams.backgroundImage = Paint.none

# }}}
# {{{ updateWidgetStyles()
proc updateWidgetStyles(a) =
  alias(cfg, a.theme.config)

  # Button
  a.theme.buttonStyle = koi.getDefaultButtonStyle()

  let w = cfg.getObjectOrEmpty("ui.widget")

  with a.theme.buttonStyle:
    cornerRadius      = w.getFloatOrDefault("corner-radius")
    fillColor         = w.getColorOrDefault("background.normal")
    fillColorHover    = w.getColorOrDefault("background.hover")
    fillColorDown     = w.getColorOrDefault("background.active")
    fillColorDisabled = w.getColorOrDefault("background.disabled")

    label.color            = w.getColorOrDefault("foreground.normal")
    label.colorHover       = label.color
    label.colorDown        = w.getColorOrDefault("foreground.active")
    label.colorActive      = label.colorDown
    label.colorActiveHover = label.colorDown
    label.colorDisabled    = w.getColorOrDefault("foreground.disabled")

  # Radio button
  a.theme.radioButtonStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.radioButtonStyle:
    buttonCornerRadius         = w.getFloatOrDefault("corner-radius")
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label.color            = w.getColorOrDefault("foreground.normal")
    label.colorHover       = label.color
    label.colorDown        = w.getColorOrDefault("foreground.active")
    label.colorActive      = label.colorDown
    label.colorActiveHover = label.colorDown

  # Icon radio button
  a.theme.iconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.iconRadioButtonsStyle:
    buttonPadHoriz             = 4.0
    buttonPadVert              = 4.0
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label.fontSize         = 18.0
    label.color            = w.getColorOrDefault("foreground.normal")
    label.colorHover       = label.color
    label.colorDown        = w.getColorOrDefault("foreground.active")
    label.colorActive      = label.colorDown
    label.colorActiveHover = label.colorDown
    label.padHoriz         = 0
    label.padHoriz         = 0

  # Text field
  a.theme.textFieldStyle = koi.getDefaultTextFieldStyle()

  let t = cfg.getObjectOrEmpty("ui.text-field")

  with a.theme.textFieldStyle:
    bgCornerRadius      = w.getFloatOrDefault("corner-radius")
    bgFillColor         = w.getColorOrDefault("background.normal")
    bgFillColorHover    = w.getColorOrDefault("background.hover")
    bgFillColorActive   = t.getColorOrDefault("edit.background")
    bgFillColorDisabled = w.getColorOrDefault("background.disabled")
    textColor           = w.getColorOrDefault("foreground.normal")
    textColorHover      = textColor
    textColorActive     = t.getColorOrDefault("edit.text")
    textColorDisabled   = w.getColorOrDefault("foreground.disabled")
    cursorColor         = t.getColorOrDefault("cursor")
    selectionColor      = t.getColorOrDefault("selection")

  # Text area
  a.theme.textAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.textAreaStyle:
    bgCornerRadius    = w.getFloatOrDefault("corner-radius")
    bgFillColor       = w.getColorOrDefault("background.normal")

    bgFillColorHover  = lerp(bgFillColor,
                             w.getColorOrDefault("background.hover"), 0.5)

    bgFillColorActive = t.getColorOrDefault("edit.background")
    textColor         = w.getColorOrDefault("foreground.normal")
    textColorHover    = textColor
    textColorActive   = t.getColorOrDefault("edit.text")
    cursorColor       = t.getColorOrDefault("cursor")
    selectionColor    = t.getColorOrDefault("selection")

    with scrollBarStyleNormal:
      let c = t.getColorOrDefault("scroll-bar.normal")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

    with scrollBarStyleEdit:
      let c = t.getColorOrDefault("scroll-bar.edit")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Check box
  a.theme.checkBoxStyle = koi.getDefaultCheckBoxStyle()

  with a.theme.checkBoxStyle:
    cornerRadius          = w.getFloatOrDefault("corner-radius")
    fillColor             = w.getColorOrDefault("background.normal")
    fillColorHover        = w.getColorOrDefault("background.hover")
    fillColorDown         = w.getColorOrDefault("background.active")
    fillColorActive       = fillColorDown
    fillColorDisabled     = w.getColorOrDefault("background.disabled")

    icon.fontSize         = 12.0
    icon.color            = w.getColorOrDefault("foreground.normal")
    icon.colorHover       = icon.color
    icon.colorDown        = w.getColorOrDefault("foreground.active")
    icon.colorActive      = icon.colorDown
    icon.colorActiveHover = icon.colorDown

    iconActive            = IconCheck
    iconInactive          = NoIcon

  # Dialog style
  a.theme.dialogStyle = koi.getDefaultDialogStyle()

  let d = cfg.getObjectOrEmpty("ui.dialog")

  with a.theme.dialogStyle:
    cornerRadius      = d.getFloatOrDefault("corner-radius")
    backgroundColor   = d.getColorOrDefault("background")
    titleBarBgColor   = d.getColorOrDefault("title.background")
    titleBarTextColor = d.getColorOrDefault("title.text")

    outerBorderColor  = d.getColorOrDefault("outer-border.color")
    innerBorderColor  = d.getColorOrDefault("inner-border.color")
    outerBorderWidth  = d.getFloatOrDefault("outer-border.width")
    innerBorderWidth  = d.getFloatOrDefault("inner-border.width")

    with shadow:
      enabled = d.getBoolOrDefault("shadow.enabled")
      xOffset = d.getFloatOrDefault("shadow.x-offset")
      yOffset = d.getFloatOrDefault("shadow.y-offset")
      feather = d.getFloatOrDefault("shadow.feather")
      color   = d.getColorOrDefault("shadow.color")

  a.theme.aboutDialogStyle = a.theme.dialogStyle.deepCopy()
  a.theme.aboutDialogStyle.drawTitleBar = false

  # Label
  a.theme.labelStyle = koi.getDefaultLabelStyle()

  with a.theme.labelStyle:
    fontSize      = 14
    color         = d.getColorOrDefault("label")
    colorDisabled = color.lerp(d.getColorOrDefault("background"), 0.7)
    align         = haLeft

  # Warning label
  a.theme.warningLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.warningLabelStyle:
    color     = d.getColorOrDefault("warning")
    multiLine = true

  # Error label
  a.theme.errorLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.errorLabelStyle:
    color     = d.getColorOrDefault("error")
    multiLine = true

  # Level drop-down
  let ld = cfg.getObjectOrEmpty("level.level-drop-down")

  a.theme.levelDropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.levelDropDownStyle:
    buttonCornerRadius       = ld.getFloatOrDefault("corner-radius")
    buttonFillColor          = ld.getColorOrDefault("button.normal")
    buttonFillColorHover     = ld.getColorOrDefault("button.hover")
    buttonFillColorDown      = buttonFillColor
    buttonFillColorDisabled  = buttonFillColor

    label.fontSize           = 15.0
    label.color              = ld.getColorOrDefault("button.label")
    label.colorHover         = label.color
    label.colorDown          = label.color
    label.colorActive        = label.color
    label.colorDisabled      = label.color
    label.align              = haCenter

    item.align               = haLeft
    item.color               = ld.getColorOrDefault("item.normal")
    item.colorHover          = ld.getColorOrDefault("item.hover")

    itemListCornerRadius     = buttonCornerRadius
    itemListPadHoriz         = 10.0
    itemListFillColor        = ld.getColorOrDefault("item-list-background")
    itemBackgroundColorHover = w.getColorOrDefault("background.active")

    var ss = koi.getDefaultShadowStyle()
    ss.color = ld.getColorOrDefault("shadow.color")
    ss.cornerRadius = buttonCornerRadius * 1.6
    shadow = ss

  # About button
  let ab = cfg.getObjectOrEmpty("ui.about-button")

  a.theme.aboutButtonStyle = koi.getDefaultButtonStyle()

  with a.theme.aboutButtonStyle:
    labelOnly        = true
    label.fontSize   = 20.0
    label.padHoriz   = 0
    label.color      = ab.getColorOrDefault("label.normal")
    label.colorHover = ab.getColorOrDefault("label.hover")
    label.colorDown  = ab.getColorOrDefault("label.down")

  # Note text area
  let pn = cfg.getObjectOrEmpty("pane.notes")

  a.theme.noteTextAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.noteTextAreaStyle:
    bgFillColor         = black(0)
    bgFillColorHover    = black(0)
    bgFillColorActive   = black(0)
    bgFillColorDisabled = black(0)

    textPadHoriz        = 0.0
    textPadVert         = 0.0
    textFontSize        = 15.0
    textFontFace        = "sans-bold"
    textLineHeight      = 1.4
    textColorDisabled   = pn.getColorOrDefault("text")

    with scrollBarStyleNormal:
      let c = pn.getColorOrDefault("scroll-bar")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

# }}}
# {{{ updateThemeStyles()
proc updateThemeStyles(a) =
  alias(cfg, a.theme.config)

  updateWidgetStyles(a)

  a.theme.statusBarStyle = cfg.getObjectOrEmpty("ui.status-bar")
                              .toStatusBarStyle()

  a.theme.toolbarPaneStyle = cfg.getObjectOrEmpty("pane.toolbar")
                                .toToolbarPaneStyle()

  a.theme.notesPaneStyle = cfg.getObjectOrEmpty("pane.notes")
                              .toNotesPaneStyle()

  a.theme.levelStyle = cfg.getObjectOrEmpty("level").toLevelStyle()

  a.theme.windowStyle = cfg.getObjectOrEmpty("ui.window").toWindowStyle()
  a.win.style = a.theme.windowStyle

  a.ui.drawLevelParams.initDrawLevelParams(a.theme.levelStyle, a.vg,
                                           koi.getPxRatio())

# }}}

# {{{ switchTheme()
proc switchTheme(themeIndex: Natural; a) =
  let theme = a.theme.themeNames[themeIndex]
  loadTheme(theme, a)

  updateThemeStyles(a)
  loadBackgroundImage(theme, a)

  a.theme.currThemeIndex = themeIndex

  a.themeEditor.modified = false
  a.theme.prevConfig = a.theme.config.deepCopy()

# }}}

# }}}
# {{{ Config handling

# {{{ loadAppConfigOrDefault()
proc loadAppConfigOrDefault(filename: string): HoconNode =
  var s: FileStream
  try:
    s = newFileStream(filename)
    var p = initHoconParser(s)
    result = p.parse()
  except CatchableError as e:
    logging.warn(
      fmt"Couldn't load config file '{filename}', using default config. " &
      fmt"Error message: {e.msg}"
    )
    result = newHoconObject()
  finally:
    if s != nil: s.close()

# }}}
# {{{ saveAppConfig()
proc saveAppConfig(cfg: HoconNode, filename: string) =
  var s: FileStream
  try:
    s = newFileStream(filename, fmWrite)
    cfg.write(s)
  except CatchableError as e:
    logging.error(
      fmt"Couldn't write config file '{filename}'. Error message: {e.msg}"
    )
  finally:
    if s != nil: s.close()

# }}}
# {{{ saveAppConfig()

proc saveAppConfig(a) =
  alias(dp, a.ui.drawLevelParams)

  let (xpos, ypos) = if a.win.maximized: a.win.unmaximizedPos else: a.win.pos

  let (width, height) = if a.win.maximized: a.win.unmaximizedSize
                        else: a.win.size

  let cur = a.ui.cursor

  var cfg = newHoconObject()

  var p = "preferences."
  cfg.set(p & "load-last-map",                  a.prefs.loadLastMap)
  cfg.set(p & "splash.show-at-startup",         a.prefs.showSplash)
  cfg.set(p & "splash.auto-close",              a.prefs.autoCloseSplash)
  cfg.set(p & "splash.auto-close-timeout-secs", a.prefs.splashTimeoutSecs)
  cfg.set(p & "auto-save.enabled",              a.prefs.autosave)
  cfg.set(p & "auto-save.frequency-mins",       a.prefs.autosaveFreqMins)
  cfg.set(p & "video.vsync",                    a.prefs.vsync)

  p = "last-state."
  cfg.set(p & "last-document", a.doc.filename)
  cfg.set(p & "theme-name",    a.currThemeName.name)

  p = "last-state.ui."
  cfg.set(p & "zoom-level",              dp.getZoomLevel())
  cfg.set(p & "current-level",           cur.level)
  cfg.set(p & "cursor.row",              cur.row)
  cfg.set(p & "cursor.column",           cur.col)
  cfg.set(p & "view-start.row",          dp.viewStartRow)
  cfg.set(p & "view-start.column",       dp.viewStartCol)
  cfg.set(p & "option.show-cell-coords", dp.drawCellCoords)
  cfg.set(p & "option.show-tools-pane",  a.opts.showToolsPane)
  cfg.set(p & "option.show-notes-pane",  a.opts.showNotesPane)
  cfg.set(p & "option.wasd-mode",        a.opts.wasdMode)
  cfg.set(p & "option.walk-mode",        a.opts.walkMode)

  p = "last-state.window."
  cfg.set(p & "maximized",      a.win.maximized)
  cfg.set(p & "show-title-bar", a.win.showTitleBar)
  cfg.set(p & "x-position",     xpos)
  cfg.set(p & "y-position",     ypos)
  cfg.set(p & "width",          width)
  cfg.set(p & "height",         height)

  saveAppConfig(cfg, a.paths.configFile)

# }}}

# }}}
# {{{ Map handling

# {{{ loadMap()
proc loadMap(filename: string; a): bool =
  info(fmt"Loading map '{filename}'...")

  try:
    let t0 = getMonoTime()
    let (map, appState) = readMapFile(filename)
    let dt = getMonoTime() - t0

    a.doc.map = map
    a.doc.filename = filename
    a.doc.lastAutosaveTime = getMonoTime()

    if appState.isSome:
      let s = appState.get

      a.updateUI = false
      a.theme.nextThemeIndex = findThemeIndex(s.themeName, a)
      a.theme.hideThemeLoadedMessage = true

      with a.opts:
        showToolsPane = s.optShowToolsPane
        showNotesPane = s.optShowNotesPane
        wasdMode      = s.optWasdMode
        walkMode      = s.optWalkMode
        drawTrail     = false

      with a.ui.drawLevelParams:
        viewStartRow   = s.viewStartRow
        viewStartCol   = s.viewStartCol
        drawCellCoords = s.optShowCellCoords

      with a.ui.cursor:
        level = s.currentLevel
        row   = s.cursorRow
        col   = s.cursorCol

      a.ui.drawLevelParams.setZoomLevel(a.theme.levelStyle, s.zoomLevel)
      a.ui.mouseCanStartExcavateAction = true

    else:
      resetCursorAndViewStart(a)

    initUndoManager(a.doc.undoManager)

    let message = fmt"Map '{filename}' loaded in " &
                  fmt"{durationToFloatMillis(dt):.2f} ms"

    info(message)
    setStatusMessage(IconFloppy, message, a)
    result = true

  except CatchableError as e:
    logError(e, "Error loading map")
    setWarningMessage(fmt"Error loading map: {e.msg}", autohide=false, a=a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ saveMap()
proc saveMap(filename: string, autosave, createBackup: bool; a) =
  alias(dp, a.ui.drawLevelParams)

  let cur = a.ui.cursor

  let appState = AppState(
    themeName         : a.currThemeName.name,
    zoomLevel         : dp.getZoomLevel(),
    currentLevel      : cur.level,
    cursorRow         : cur.row,
    cursorCol         : cur.col,
    viewStartRow      : dp.viewStartRow,
    viewStartCol      : dp.viewStartCol,
    optShowCellCoords : dp.drawCellCoords,
    optShowToolsPane  : a.opts.showToolsPane,
    optShowNotesPane  : a.opts.showNotesPane,
    optWasdMode       : a.opts.wasdMode,
    optWalkMode       : a.opts.walkMode,
  )

  info(fmt"Saving map to '{filename}'")

  if createBackup:
    try:
      if fileExists(filename):
        moveFile(filename, fmt"{filename}.{BackupFileExt}")
    except CatchableError as e:
      logError(e, "Error creating backup file")
      setWarningMessage(fmt"Error creating backup file: {e.msg}",
                        autohide=false, a=a)
      a.logFile.flushFile()
      return

  try:
    writeMapFile(a.doc.map, appState, filename)
    a.doc.undoManager.setLastSaveState()

    if not autosave:
      setStatusMessage(IconFloppy, fmt"Map '{filename}' saved", a)

  except CatchableError as e:
    logError(e, "Error saving map")
    let prefix = if autosave: "Autosave failed: " else: ""
    setWarningMessage(fmt"{prefix}Error saving map: {e.msg}", autohide=false,
                      a=a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ handleAutoSaveMap()
proc handleAutoSaveMap(a) =
  if a.prefs.autosave and a.doc.undoManager.isModified:
    let dt = getMonoTime() - a.doc.lastAutosaveTime
    if dt > initDuration(minutes = a.prefs.autosaveFreqMins):
      let filename = if a.doc.filename == "":
                       a.paths.autosaveDir / addFileExt("Untitled", MapFileExt)
                     else: a.doc.filename

      saveMap(filename, autosave=true, createBackup=true, a)
      a.doc.lastAutosaveTime = getMonoTime()

# }}}
# {{{ autoSaveMapOnCrash()

when not defined(DEBUG):

  proc autoSaveMapOnCrash(a): string =
    var fname: string
    if a.doc.filename == "":
      let (path, _, _) = splitFile(a.doc.filename)
      fname = path
    else:
      fname = a.paths.autosaveDir

    fname = fname / CrashAutosaveFilename

    info(fmt"Auto-saving map to '{fname}'")
    saveMap(fname, autosave=false, createBackup=false, a)

    result = fname

# }}}

# }}}
# {{{ Dialogs

# {{{ Constants
const
  DlgItemHeight   = 24.0
  DlgButtonWidth  = 80.0
  DlgButtonPad    = 10.0
  DlgNumberWidth  = 50.0
  DlgCheckBoxSize = 18.0
  DlgTopPad       = 50.0
  DlgTopNoTabPad  = 60.0
  DlgLeftPad      = 30.0
  DlgTabBottomPad = 50.0

  ConfirmDlgWidth  = 350.0
  ConfirmDlgHeight = 160.0

  DialogLayoutParams = AutoLayoutParams(
    itemsPerRow      : 2,
    rowWidth         : 370.0,
    labelWidth       : 160.0,
    sectionPad       : 0.0,
    leftPad          : 0.0,
    rightPad         : 0.0,
    rowPad           : 8.0,
    rowGroupPad      : 20.0,
    defaultRowHeight : 24.0
  )

# }}}
# {{{ Helpers

# {{{ coordinateFields()
template coordinateFields() =
  const LetterLabelWidth = 100

  group:
    koi.label("Origin", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Northwest", "Southwest"],
      dlg.origin,
      style = a.theme.radioButtonStyle
    )

  group:
    koi.label("Column style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.columnStyle,
      style = a.theme.radioButtonStyle
    )

    koi.label("Row style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.rowStyle,
      style = a.theme.radioButtonStyle
    )

  group:
    let letterLabelX = x + 190

    koi.label("Column start", style=a.theme.labelStyle)
    var y = koi.currAutoLayoutY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.columnStart,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordColumnStartLimits.minInt,
        maxInt: CoordColumnStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.columnStyle) == csLetter:
      try:
        let i = parseInt(dlg.columnStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
      except ValueError:
        discard

    koi.label("Row start", style=a.theme.labelStyle)
    y = koi.currAutoLayoutY()


    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rowStart,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordRowStartLimits.minInt,
        maxInt: CoordRowStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.rowStyle) == csLetter:
      try:
        let i = parseInt(dlg.rowStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
      except ValueError:
        discard

# }}}
# {{{ regionFields()
template regionFields() =
  group:
    koi.label("Enable regions", style=a.theme.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.enableRegions, style = a.theme.checkBoxStyle)

    if dlg.enableRegions:
      group:
        koi.label("Region columns", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.colsPerRegion,
          activate = dlg.activateFirstTextField,
          constraint = TextFieldConstraint(
            kind:   tckInteger,
            minInt: RegionColumnLimits.minInt,
            maxInt: RegionColumnLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

        koi.label("Region rows", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.rowsPerRegion,
          constraint = TextFieldConstraint(
            kind:   tckInteger,
            minInt: RegionRowLimits.minInt,
            maxInt: RegionRowLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

      group:
        koi.label("Per-region coordinates", style=a.theme.labelStyle)

        koi.nextItemHeight(DlgCheckBoxSize)
        koi.checkBox(dlg.perRegionCoords, style = a.theme.checkBoxStyle)

# }}}
# {{{ noteFields()
template noteFields(dlgWidth: float) =
  koi.label("Notes", style=a.theme.labelStyle)

  koi.textArea(
    x=0, y=28, w=dlgWidth-60, h=187,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

# }}}
# {{{ commonLevelFields()
template commonLevelFields(dimensionsDisabled: bool) =
  group:
    koi.label("Location name", style=a.theme.labelStyle)

    koi.textField(
      dlg.locationName,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckString,
        minLen: LevelLocationNameLimits.minRuneLen,
        maxLen: LevelLocationNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Level name", style=a.theme.labelStyle)

    koi.textField(
      dlg.levelName,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: LevelNameLimits.minRuneLen,
        maxLen: LevelNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Elevation", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.elevation,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelElevationLimits.minInt,
        maxInt: LevelElevationLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Columns", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.cols,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelColumnsLimits.minInt,
        maxInt: LevelColumnsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
      style = a.theme.textFieldStyle
    )

    koi.label("Rows", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rows,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelRowsLimits.minInt,
        maxInt: LevelRowsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
      style = a.theme.textFieldStyle
    )

# }}}
# {{{ validateLevelFields()
template validateLevelFields(dlg, map, validationError: untyped) =
  if dlg.locationName == "":
    validationError = mkValidationError("Location name is mandatory")
  else:
    for l in map.levels:
      if l.locationName == dlg.locationName and
         l.levelName == dlg.levelName and
         $l.elevation == dlg.elevation:

        validationError = mkValidationError(
          "A level already exists with the same location name, " &
          "level name and elevation."
        )
        break

# }}}
# {{{ commonGeneralMapFields()
template commonGeneralMapFields(map: Map, displayCreationTime: bool) =
  group:
    koi.label("Title", style=a.theme.labelStyle)

    koi.textField(
      dlg.title,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapTitleLimits.minRuneLen,
        maxLen: MapTitleLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Game", style=a.theme.labelStyle)

    koi.textField(
      dlg.game,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapGameLimits.minRuneLen,
        maxLen: MapGameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Author", style=a.theme.labelStyle)

    koi.textField(
      dlg.author,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapAuthorLimits.minRuneLen,
        maxLen: MapAuthorLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    if displayCreationTime:
      koi.label("Creation time", style=a.theme.labelStyle)

      koi.textField(
        map.creationTime,
        disabled = true,
        style = a.theme.textFieldStyle
      )

# }}}
# {{{ validateCommonGeneralMapFields()
template validateCommonGeneralMapFields(dlg: untyped): string =
  if dlg.title == "":
    mkValidationError("Title is mandatory")
  else: ""

# }}}

# {{{ calcDialogX()
proc calcDialogX(dlgWidth: float; a): float =
  drawAreaWidth(a)*0.5 - dlgWidth*0.5

# }}}
# {{{ dialogButtonsStartPos()
func dialogButtonsStartPos(dlgWidth, dlgHeight: float,
                           numButtons: Natural): (float, float) =
  const BorderPad = 15.0

  let x = dlgWidth - numButtons * DlgButtonWidth - BorderPad -
          (numButtons-1) * DlgButtonPad

  let y = dlgHeight - DlgItemHeight - BorderPad

  result = (x, y)

# }}}
# {{{ mkValidationError()
func mkValidationError(msg: string): string =
  fmt"{IconWarning}   {msg}"

# }}}
# {{{ mkValidationWarning()
func mkValidationWarning(msg: string): string =
  fmt"{IconInfo}   {msg}"

# }}}
# {{{ moveGridPositionWrapping()
func moveGridPositionWrapping(currIdx: int, dc: int = 0, dr: int = 0,
                              numItems, itemsPerRow: Natural): Natural =
  assert numItems mod itemsPerRow == 0

  let numRows = ceil(numItems.float / itemsPerRow).Natural
  var row = currIdx div itemsPerRow
  var col = currIdx mod itemsPerRow
  col = floorMod(col+dc, itemsPerRow).Natural
  row = floorMod(row+dr, numRows).Natural
  result = row * itemsPerRow + col

# }}}
# {{{ handleGridRadioButton()
func handleGridRadioButton(ke: Event, currButtonIdx: Natural,
                           numButtons, buttonsPerRow: Natural): Natural =

  proc move(dc: int = 0, dr: int = 0): Natural =
    moveGridPositionWrapping(currButtonIdx, dc, dr, numButtons, buttonsPerRow)

  result =
    if   ke.isKeyDown(MoveKeysCursor.left,  repeat=true): move(dc = -1)
    elif ke.isKeyDown(MoveKeysCursor.right, repeat=true): move(dc =  1)
    elif ke.isKeyDown(MoveKeysCursor.up,    repeat=true): move(dr = -1)
    elif ke.isKeyDown(MoveKeysCursor.down,  repeat=true): move(dr =  1)
    else: currButtonIdx

# }}}
# {{{ handleTabNavigation()
proc handleTabNavigation(ke: Event,
                         currTabIndex, maxTabIndex: Natural): Natural =
  result = currTabIndex

  if ke.isKeyDown(MoveKeysCursor.left, {mkCtrl}) or
     ke.isKeyDown(keyTab, {mkCtrl, mkShift}):
    if    currTabIndex > 0: result = currTabIndex - 1
    else: result = maxTabIndex

  elif ke.isKeyDown(MoveKeysCursor.right, {mkCtrl}) or
       ke.isKeyDown(keyTab, {mkCtrl}):
    if    currTabIndex < maxTabIndex: result = currTabIndex + 1
    else: result = 0

  else:
    let i = ord(ke.key) - ord(key1)
    if ke.action == kaDown and mkCtrl in ke.mods and
      i >= 0 and i <= maxTabIndex:
      result = i

# }}}

# {{{ colorRadioButtonDrawProc()
proc colorRadioButtonDrawProc(colors: seq[Color],
                              cursorColor: Color): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               state: WidgetState, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    let sw = 2.0
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    var col = colors[buttonIdx]

    let cursorColor = if state == wsHover: cursorColor.withAlpha(0.65)
                      else: cursorColor

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if state in {wsDown, wsActive, wsActiveHover, wsHover}:
      vg.beginPath()
      vg.strokeColor(cursorColor)
      vg.strokeWidth(sw)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.stroke()

      cx = x+SelPad
      cy = y+SelPad
      cw = w-Pad-SelPad*2
      ch = h-Pad-SelPad*2

    else:
      cx = x
      cy = y
      cw = w-Pad
      ch = h-Pad

    vg.beginPath()
    vg.fillColor(col)
    vg.rect(cx, cy, cw, ch)
    vg.fill()

# }}}

# {{{ closeDialog()
proc closeDialog(a) =
  koi.closeDialog()
  a.dialogs.activeDialog = dlgNone

# }}}

# }}}

# {{{ About dialog
proc openAboutDialog(a) =
  a.dialogs.activeDialog = dlgAboutDialog

proc openUserManual(a)
proc openWebsite(a)
proc openForum(a)

proc aboutDialog(a) =
  alias(al, a.aboutLogo)
  alias(vg, a.vg)

  const
    DlgWidth = 370.0
    DlgHeight = 440.0

  let
    dialogX = floor(calcDialogX(DlgWidth, a))
    dialogY = floor((koi.winHeight() - DlgHeight) * 0.5)

  let logoColor = a.theme.config.getColorOrDefault("ui.about-dialog.logo")

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconQuestion}  About Gridmonger",
                  x=dialogX.some, y=dialogY.some,
                  style=a.theme.aboutDialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad
  let w = DlgWidth
  let h = DlgItemHeight

  if al.logoImage == NoImage or al.updateLogoImage:
    colorImage(al.logo, logoColor)
    if al.logoImage == NoImage:
      al.logoImage = createImage(al.logo)
    else:
      vg.updateImage(al.logoImage, cast[ptr byte](al.logo.data))
    al.updateLogoImage = false

  let scale = DlgWidth / al.logo.width

  al.logoPaint = createPattern(a.vg, al.logoImage, alpha=logoColor.a,
                               xoffs=dialogX, yoffs=dialogY, scale=scale)


  koi.image(0, 0, DlgWidth.float, DlgHeight.float, al.logoPaint)

  var labelStyle = a.theme.labelStyle.deepCopy()
  labelStyle.align = haCenter

  y += 265
  koi.label(0, y, w, h, VersionInfo, style=labelStyle)

  y += 25
  koi.label(0, y, w, h, DevelopedByInfo, style=labelStyle)

  x = (DlgWidth - (3*DlgButtonWidth + 2*DlgButtonPad)) * 0.5
  y += 50
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Manual",
                style=a.theme.buttonStyle):
    openUserManual(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Website",
                style=a.theme.buttonStyle):
    openWebsite(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Forum",
                style=a.theme.buttonStyle):
    openForum(a)

  proc closeAction(a) =
    a.aboutLogo.updateLogoImage = true
    closeDialog(a)


  # HACK, HACK, HACK!
  if not a.opts.showThemeEditor:
    if not koi.hasHotItem() and koi.hasEvent():
      let ev = koi.currEvent()
      if ev.kind == ekMouseButton and ev.button == mbLeft and ev.pressed:
        closeAction(a)

  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scCancel) or ke.isShortcutDown(scAccept):
      closeAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Preferences dialog
proc openPreferencesDialog(a) =
  alias(dlg, a.dialogs.preferencesDialog)

  dlg.showSplash        = a.prefs.showSplash
  dlg.autoCloseSplash   = a.prefs.autoCloseSplash
  dlg.splashTimeoutSecs = $a.prefs.splashTimeoutSecs
  dlg.loadLastMap       = a.prefs.loadLastMap
  dlg.vsync             = a.prefs.vsync
  dlg.autosave          = a.prefs.autosave
  dlg.autosaveFreqMins  = $a.prefs.autosaveFreqMins

  a.dialogs.activeDialog = dlgPreferencesDialog


proc preferencesDialog(dlg: var PreferencesDialogParams; a) =
  const
    DlgWidth = 370.0
    DlgHeight = 296.0
    TabWidth = 180.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCog}  Preferences",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["Startup", "General"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 220
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # Startup
    group:
      koi.label("Show splash image", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.showSplash, style = a.theme.checkBoxStyle)


      var disabled = not dlg.showSplash
      koi.label("Auto-close splash",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autoCloseSplash, disabled=disabled,
                   style = a.theme.checkBoxStyle)


      disabled = not (dlg.showSplash and dlg.autoCloseSplash)
      koi.label("Auto-close timeout (seconds)",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.splashTimeoutSecs,
        activate = dlg.activateFirstTextField,
        disabled = disabled,
        constraint = TextFieldConstraint(
          kind:   tckInteger,
          minInt: SplashTimeoutSecsLimits.minInt,
          maxInt: SplashTimeoutSecsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Load last map", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.loadLastMap, style = a.theme.checkBoxStyle)


  elif dlg.activeTab == 1:  # General
    group:
      let autosaveDisabled = not dlg.autosave

      koi.label("Autosave", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autosave, style = a.theme.checkBoxStyle)

      koi.label("Autosave frequency (minutes)",
                state = if autosaveDisabled: wsDisabled else: wsNormal,
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.autosaveFreqMins,
        activate = dlg.activateFirstTextField,
        disabled = autosaveDisabled,
        constraint = TextFieldConstraint(
          kind:   tckInteger,
          minInt: AutosaveFreqMinsLimits.minInt,
          maxInt: AutosaveFreqMinsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Enable vertical sync", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.vsync, style = a.theme.checkBoxStyle)

  koi.endView()


  proc okAction(dlg: PreferencesDialogParams; a) =
    a.prefs.showSplash        = dlg.showSplash
    a.prefs.autoCloseSplash   = dlg.autoCloseSplash
    a.prefs.splashTimeoutSecs = parseInt(dlg.splashTimeoutSecs).Natural
    a.prefs.loadLastMap       = dlg.loadLastMap
    a.prefs.vsync             = dlg.vsync
    a.prefs.autosave          = dlg.autosave
    a.prefs.autosaveFreqMins  = parseInt(dlg.autosaveFreqMins).Natural

    saveAppConfig(a)
    setSwapInterval(a)

    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Save/discard map changes dialog
proc openSaveDiscardMapDialog(action: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardMapDialog)
  dlg.action = action
  a.dialogs.activeDialog = dlgSaveDiscardMapDialog


proc saveMap(a)

proc saveDiscardMapDialog(dlg: var SaveDiscardMapDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Map?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made change to the map.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the map first?",
    style=a.theme.labelStyle
  )

  proc saveAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    saveMap(a)
    dlg.action(a)

  proc discardAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    dlg.action(a)

  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.theme.buttonStyle):
    saveAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel):  cancelAction(a)
    elif ke.isShortcutDown(scDiscard): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept):  saveAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New map dialog
proc openNewMapDialog(a) =
  alias(dlg, a.dialogs.newMapDialog)

  with a.doc.map.coordOpts:
    dlg.title        = "Untitled Map"
    dlg.game         = ""
    dlg.author       = ""

    dlg.origin       = origin.ord
    dlg.rowStyle     = rowStyle.ord
    dlg.columnStyle  = columnStyle.ord
    dlg.rowStart     = $rowStart
    dlg.columnStart  = $columnStart

    dlg.notes        = ""

  dlg.activeTab = 0

  a.dialogs.activeDialog = dlgNewMapDialog


proc newMapDialog(dlg: var NewMapDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Map",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonGeneralMapFields(a.doc.map, displayCreationTime=false)

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = validateCommonGeneralMapFields(dlg)

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: NewMapDialogParams; a) =
    if validationError != "": return

    a.opts.drawTrail = false

    a.doc.filename = ""
    a.doc.map = newMap(dlg.title, dlg.game, dlg.author,
                       creationTime=now().format("yyyy-MM-dd HH:mm:ss"))

    with a.doc.map.coordOpts:
      origin      = CoordinateOrigin(dlg.origin)
      rowStyle    = CoordinateStyle(dlg.rowStyle)
      columnStyle = CoordinateStyle(dlg.columnStyle)
      rowStart    = parseInt(dlg.rowStart)
      columnStart = parseInt(dlg.columnStart)

    a.doc.map.notes = dlg.notes

    initUndoManager(a.doc.undoManager)

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, "New map created", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit map properties dialog
proc openEditMapPropsDialog(a) =
  alias(dlg, a.dialogs.editMapPropsDialog)
  alias(map, a.doc.map)

  dlg.title        = map.title
  dlg.game         = map.game
  dlg.author       = map.author

  with map.coordOpts:
    dlg.origin      = origin.ord
    dlg.rowStyle    = rowStyle.ord
    dlg.columnStyle = columnStyle.ord
    dlg.rowStart    = $rowStart
    dlg.columnStart = $columnStart

  dlg.notes = map.notes

  a.dialogs.activeDialog = dlgEditMapPropsDialog


proc editMapPropsDialog(dlg: var EditMapPropsDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  Edit Map Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonGeneralMapFields(a.doc.map, displayCreationTime=true)

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = validateCommonGeneralMapFields(dlg)

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: EditMapPropsDialogParams; a) =
    if validationError != "": return

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    actions.setMapProperties(a.doc.map, a.ui.cursor,
                             dlg.title, dlg.game, dlg.author,
                             coordOpts, dlg.notes, a.doc.undoManager)

    setStatusMessage(IconFile, "Map properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New level dialog
proc openNewLevelDialog(a) =
  alias(dlg, a.dialogs.newLevelDialog)

  let map = a.doc.map
  var co: CoordinateOptions

  if map.hasLevels:
    let l = currLevel(a)
    dlg.locationName = l.locationName
    dlg.levelName = ""
    dlg.elevation = if   l.elevation > 0: $(l.elevation + 1)
                    elif l.elevation < 0: $(l.elevation - 1)
                    else: "0"
    dlg.rows = $l.rows
    dlg.cols = $l.cols
    dlg.overrideCoordOpts = l.overrideCoordOpts

    co = coordOptsForCurrLevel(a)

  else:
    dlg.locationName = "Untitled Location"
    dlg.levelName = ""
    dlg.elevation = "0"
    dlg.rows = "16"
    dlg.cols = "16"
    dlg.overrideCoordOpts = false

    co = map.coordOpts

  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.enableRegions   = false
  dlg.colsPerRegion   = "16"
  dlg.rowsPerRegion   = "16"
  dlg.perRegionCoords = true

  dlg.activeTab = 0

  a.dialogs.activeDialog = dlgNewLevelDialog


proc newLevelDialog(dlg: var LevelPropertiesDialogParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 460.0
    DlgHeight = 436.0
    TabWidth = 400.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Level",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonLevelFields(dimensionsDisabled = false)

  elif dlg.activeTab == 1:  # Coordinates
    group:
      koi.label("Override map settings", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.overrideCoordOpts, style = a.theme.checkBoxStyle)

      if dlg.overrideCoordOpts:
        coordinateFields()

  elif dlg.activeTab == 2:  # Regions
    regionFields()

  elif dlg.activeTab == 3:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = ""
  validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
    if validationError != "": return

    a.opts.drawTrail = false

    let
      rows = parseInt(dlg.rows)
      cols = parseInt(dlg.cols)

    let cur = actions.addNewLevel(
      a.doc.map,
      a.ui.cursor,
      locationName = dlg.locationName,
      levelName = dlg.levelName,
      elevation = parseInt(dlg.elevation),
      rows = rows,
      cols = cols,
      dlg.overrideCoordOpts,

      coordOpts = CoordinateOptions(
        origin      : CoordinateOrigin(dlg.origin),
        rowStyle    : CoordinateStyle(dlg.rowStyle),
        columnStyle : CoordinateStyle(dlg.columnStyle),
        rowStart    : parseInt(dlg.rowStart),
        columnStart : parseInt(dlg.columnStart)
      ),

      regionOpts = RegionOptions(
        enabled         : dlg.enableRegions,
        colsPerRegion   : parseInt(dlg.colsPerRegion),
        rowsPerRegion   : parseInt(dlg.rowsPerRegion),
        perRegionCoords : dlg.perRegionCoords
      ),

      dlg.notes,
      a.doc.undoManager
    )
    setCursor(cur, a)

    setStatusMessage(IconFile, fmt"New {rows}×{cols} level created", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit level properties dialog
proc openEditLevelPropsDialog(a) =
  alias(dlg, a.dialogs.editLevelPropsDialog)

  let l = currLevel(a)

  dlg.locationName = l.locationName
  dlg.levelName = l.levelName
  dlg.elevation = $l.elevation
  dlg.rows = $l.rows
  dlg.cols = $l.cols

  let co = coordOptsForCurrLevel(a)
  dlg.overrideCoordOpts = l.overrideCoordOpts
  dlg.origin            = co.origin.ord
  dlg.rowStyle          = co.rowStyle.ord
  dlg.columnStyle       = co.columnStyle.ord
  dlg.rowStart          = $co.rowStart
  dlg.columnStart       = $co.columnStart

  let ro = l.regionOpts
  dlg.enableRegions   = ro.enabled
  dlg.colsPerRegion   = $ro.colsPerRegion
  dlg.rowsPerRegion   = $ro.rowsPerRegion
  dlg.perRegionCoords = ro.perRegionCoords

  dlg.notes = l.notes

  a.dialogs.activeDialog = dlgEditLevelPropsDialog


proc editLevelPropsDialog(dlg: var LevelPropertiesDialogParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 460.0
    DlgHeight = 436.0
    TabWidth = 400.0

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconNewFile}  Edit Level Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonLevelFields(dimensionsDisabled = true)

  elif dlg.activeTab == 1:  # Coordinates
    koi.label("Override map settings", style=a.theme.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.overrideCoordOpts, style = a.theme.checkBoxStyle)

    if dlg.overrideCoordOpts:
      coordinateFields()

  elif dlg.activeTab == 2:  # Regions
    regionFields()

  elif dlg.activeTab == 3:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""

  let l = currLevel(a)
  if dlg.locationName != l.locationName or
     dlg.levelName != l.levelName or
     dlg.elevation != $l.elevation:

    validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
    if validationError != "": return

    let elevation = parseInt(dlg.elevation)

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    let regionOpts = RegionOptions(
      enabled         : dlg.enableRegions,
      rowsPerRegion   : parseInt(dlg.rowsPerRegion),
      colsPerRegion   : parseInt(dlg.colsPerRegion),
      perRegionCoords : dlg.perRegionCoords
    )

    actions.setLevelProperties(a.doc.map, a.ui.cursor,
                               dlg.locationName, dlg.levelName, elevation,
                               dlg.overrideCoordOpts, coordOpts, regionOpts,
                               dlg.notes,
                               a.doc.undoManager)

    setStatusMessage(fmt"Level properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Resize level dialog
proc openResizeLevelDialog(a) =
  alias(dlg, a.dialogs.resizeLevelDialog)

  let l = currLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter

  a.dialogs.activeDialog = dlgResizeLevelDialog


proc resizeLevelDialog(dlg: var ResizeLevelDialogParams; a) =
  const
    DlgWidth = 270.0
    DlgHeight = 300.0
    LabelWidth = 80.0
    PadYSmall = 32
    PadYLarge = 40

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCrop}  Resize Level",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Columns", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.cols,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
      minInt: LevelColumnsLimits.minInt,
      maxInt: LevelColumnsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  y += PadYSmall
  koi.label(x, y, LabelWidth, h, "Rows", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.rows,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
      minInt: LevelRowsLimits.minInt,
      maxInt: LevelRowsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  const IconsPerRow = 3

  const AnchorIcons = @[
    IconArrowUpLeft,   IconArrowUp,   IconArrowUpRight,
    IconArrowLeft,     IconCircleInv, IconArrowRight,
    IconArrowDownLeft, IconArrowDown, IconArrowDownRight
  ]

  y += PadYLarge
  koi.label(x, y, LabelWidth, h, "Anchor", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 35, 35,
    labels = AnchorIcons,
    dlg.anchor,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: IconsPerRow),
    style = a.theme.iconRadioButtonsStyle
  )

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  dlg.activateFirstTextField = false


  proc okAction(dlg: ResizeLevelDialogParams; a) =
    let newRows = parseInt(dlg.rows)
    let newCols = parseInt(dlg.cols)

    let align = case dlg.anchor
    of raTopLeft:     NorthWest
    of raTop:         North
    of raTopRight:    NorthEast
    of raLeft:        West
    of raCenter:      {}
    of raRight:       East
    of raBottomLeft:  SouthWest
    of raBottom:      South
    of raBottomRight: SouthEast

    let newCur = actions.resizeLevel(a.doc.map, a.ui.cursor, newRows, newCols,
                                     align, a.doc.undoManager)
    moveCursorTo(newCur, a)

    a.opts.drawTrail = false

    setStatusMessage(IconCrop, "Level resized", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.anchor = ResizeAnchor(
      handleGridRadioButton(ke, ord(dlg.anchor), AnchorIcons.len, IconsPerRow)
    )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Delete level dialog
proc openDeleteLevelDialog(a) =
  a.dialogs.activeDialog = dlgDeleteLevelDialog


proc deleteLevelDialog(a) =
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)

  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = 136.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete level?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "Do you want to delete the current level?",
            style=a.theme.labelStyle)

  proc deleteAction(a) =
    a.opts.drawTrail = false

    let cur = actions.deleteLevel(map, a.ui.cursor, um)
    setCursor(cur, a)

    setStatusMessage(IconTrash, "Level deleted", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.theme.buttonStyle):
    deleteAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): deleteAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit note dialog
proc openEditNoteDialog(a) =
  alias(dlg, a.dialogs.editNoteDialog)

  let cur = a.ui.cursor
  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let note = l.getNote(cur.row, cur.col)

  if note.isSome:
    let note = note.get
    dlg.editMode = true
    dlg.kind = note.kind
    dlg.text = note.text

    if note.kind == akIndexed:
      dlg.index = note.index
      dlg.indexColor = note.indexColor
    elif note.kind == akIcon:
      dlg.icon = note.icon

    if note.kind == akCustomId:
      dlg.customId = note.customId
    else:
      dlg.customId = ""

  else:
    dlg.editMode = false
    dlg.customId = ""
    dlg.text = ""

  a.dialogs.activeDialog = dlgEditNoteDialog


proc editNoteDialog(dlg: var EditNoteDialogParams; a) =
  let ls = a.theme.levelStyle

  const
    DlgWidth = 486.0
    DlgHeight = 401.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "Marker", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, w=296, h,
    labels = @["None", "Number", "ID", "Icon"],
    dlg.kind,
    style = a.theme.radioButtonStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.noteIndexBackgroundColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of akIndexed:
    koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)

    koi.radioButtons(
      x + LabelWidth, y, 28, 28,
      labels = newSeq[string](ls.noteIndexBackgroundColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc = colorRadioButtonDrawProc(
        ls.noteIndexBackgroundColor.toSeq,
        a.theme.radioButtonStyle.buttonFillColorActive
      ).some
    )

  of akCustomId:
    koi.label(x, y, LabelWidth, h, "ID", style=a.theme.labelStyle)
    koi.textField(
      x + LabelWidth, y, w=DlgNumberWidth, h,
      dlg.customId,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: NoteCustomIdLimits.minRuneLen,
        maxLen: NoteCustomIdLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  of akIcon:
    koi.label(x, y, LabelWidth, h, "Icon", style=a.theme.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 35, 35,
      labels = NoteIcons,
      dlg.icon,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 10),
      style = a.theme.iconRadioButtonsStyle
    )

  of akComment, akLabel: discard

  dlg.activateFirstTextField = false

  # Validation
  var validationErrors: seq[string] = @[]

  if dlg.kind in {akComment, akIndexed}:
    if dlg.text == "":
      validationErrors.add(mkValidationError("Text is mandatory"))
  if dlg.kind == akCustomId:
    if dlg.customId == "":
      validationErrors.add(mkValidationError("ID is mandatory"))
    else:
      for c in dlg.customId:
        if not isAlphaNumeric(c):
          validationErrors.add(
            mkValidationError(
              "ID must contain only alphanumeric characters (a-z, A-Z, 0-9)"
            )
          )
          break

  y += 45

  for err in validationErrors:
    koi.label(x, y, DlgWidth, h, err, style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditNoteDialogParams; a) =
    if validationErrors.len > 0: return

    var note = Annotation(
      kind: dlg.kind,
      text: dlg.text
    )
    case note.kind
    of akCustomId: note.customId = dlg.customId
    of akIndexed:  note.indexColor = dlg.indexColor
    of akIcon:     note.icon = dlg.icon
    of akComment, akLabel: discard

    actions.setNote(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set cell note", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=validationErrors.len > 0,
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.kind = AnnotationKind(
      handleTabNavigation(ke, ord(dlg.kind), ord(akIcon))
    )

    case dlg.kind
    of akComment, akCustomId, akLabel: discard
    of akIndexed:
      dlg.indexColor = handleGridRadioButton(
        ke, dlg.indexColor, NumIndexColors, buttonsPerRow=NumIndexColors
      )
    of akIcon:
      dlg.icon = handleGridRadioButton(
        ke, dlg.icon, NoteIcons.len, IconsPerRow
      )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit label dialog
proc openEditLabelDialog(a) =
  alias(dlg, a.dialogs.editLabelDialog)

  let cur = a.ui.cursor
  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let label = l.getLabel(cur.row, cur.col)

  if label.isSome:
    let label = label.get
    dlg.editMode = true
    dlg.text = label.text
    dlg.color = label.labelColor
  else:
    dlg.editMode = false
    dlg.text = ""

  a.dialogs.activeDialog = dlgEditLabelDialog


proc editLabelDialog(dlg: var EditLabelDialogParams; a) =
  let ls = a.theme.levelStyle

  const
    DlgWidth = 486.0
    DlgHeight = 288.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Label"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.noteIndexBackgroundColor.len

  koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, w=28, h=28,
    labels = newSeq[string](ls.labelTextColor.len),
    dlg.color,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc = colorRadioButtonDrawProc(
      ls.labelTextColor.toSeq,
      a.theme.radioButtonStyle.buttonFillColorActive
    ).some,
    style = a.theme.radioButtonStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.text == "":
    validationError = mkValidationError("Text is mandatory")

  y += 44

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditLabelDialogParams; a) =
    if validationError != "": return

    var note = Annotation(kind: akLabel, text: dlg.text, labelColor: dlg.color)
    actions.setLabel(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set label", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.color = handleGridRadioButton(
      ke, dlg.color, NumIndexColors, buttonsPerRow=NumIndexColors
    )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit region properties dialog
proc openEditRegionPropertiesDialog(a) =
  alias(dlg, a.dialogs.editRegionPropsDialog)

  let region = currRegion(a).get
  dlg.name  = region.name
  dlg.notes = region.notes

  a.dialogs.activeDialog = dlgEditRegionPropsDialog


proc editRegionPropsDialog(dlg: var EditRegionPropsParams; a) =
  const
    DlgWidth = 486.0
    DlgHeight = 348.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let l = currLevel(a)

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconCommentInv}  Edit Region Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=294, h,
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: RegionNameLimits.minRuneLen,
      maxLen: RegionNameLimits.maxRuneLen.some
    ).some,
    style = a.theme.textFieldStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Notes", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=149,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")
  else:
    if dlg.name != currRegion(a).get.name:
      for name in l.regionNames:
        if name == dlg.name:
          validationError = mkValidationError(
            "A region already exists with the same name"
          )
          break

  y += 172

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.errorLabelStyle)
    y += h


  proc okAction(dlg: EditRegionPropsParams; a) =
    alias(map, a.doc.map)
    let cur = a.ui.cursor

    let regionCoords = map.getRegionCoords(cur)
    let region = Region(name: dlg.name, notes: dlg.notes)

    actions.setRegionProperties(map, cur, regionCoords, region,
                                a.doc.undoManager)

    setStatusMessage(IconComment, "Region properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Save/discard theme changes dialog
proc openSaveDiscardThemeDialog(action: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardThemeDialog)
  dlg.action = action
  a.dialogs.activeDialog = dlgSaveDiscardThemeDialog


proc saveDiscardThemeDialog(dlg: SaveDiscardThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made changes to the theme.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the theme first?",
    style=a.theme.labelStyle
  )

  proc saveAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    saveTheme(a)
    dlg.action(a)

  proc discardAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    dlg.action(a)

  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.theme.buttonStyle):
    saveAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel):  cancelAction(a)
    elif ke.isShortcutDown(scDiscard): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept):  saveAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Overwrite theme dialog
proc openOverwriteThemeDialog(themeName: string,
                              action: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.overwriteThemeDialog)

  dlg.themeName = themeName
  dlg.action = action

  a.dialogs.activeDialog = dlgOverwriteThemeDialog


proc overwriteThemeDialog(dlg: OverwriteThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Overwrite Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h,
            fmt"User theme '{dlg.themeName}' already exists.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to overwrite it?",
    style=a.theme.labelStyle
  )

  proc overwriteAction(dlg: OverwriteThemeDialogParams; a) =
    closeDialog(a)
    dlg.action(a)

  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  x -= 20
  if koi.button(x, y, DlgButtonWidth+20, h, fmt"{IconCheck} Overwrite",
                style = a.theme.buttonStyle):
    overwriteAction(dlg, a)

  x += 20
  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): overwriteAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Copy theme dialog

proc openCopyThemeDialog(a) =
  alias(dlg, a.dialogs.copyThemeDialog)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgCopyThemeDialog


proc copyThemeDialog(dlg: var CopyThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCopy}  Copy Theme",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "New Theme Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=196, h,
    dlg.newThemeName,
    activate = dlg.activateFirstTextField,
    # TODO disallow invalid filename chars?
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if not utils.isValidFilename(dlg.newThemeName):
    validationError = "Theme name is invalid"

  var validationWarning = ""
  let idx = findThemeIndex(dlg.newThemeName, a)
  if idx.isSome:
    let theme = a.theme.themeNames[idx.get]
    if theme.userTheme:
      validationWarning = "A user theme with this name already exists"
    else:
      validationWarning = "Built-in theme will be shadowed by this name"

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationError(validationError),
              style=a.theme.errorLabelStyle)

  elif validationWarning != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationWarning(validationWarning),
              style=a.theme.warningLabelStyle)


  proc copyAction(dlg: CopyThemeDialogParams; a) =
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc copyTheme(a) =
      if copyTheme(a.currThemeName, newThemePath, a):
        buildThemeList(a)
        a.theme.nextThemeIndex = findThemeIndex(dlg.newThemeName, a)

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, action=copyTheme, a)
    else:
      copyTheme(a)

    closeDialog(a)



  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = validationError != "", style = a.theme.buttonStyle):
    copyAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): copyAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Rename theme dialog

proc openRenameThemeDialog(a) =
  alias(dlg, a.dialogs.renameThemeDialog)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgRenameThemeDialog


proc renameThemeDialog(dlg: var RenameThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFile}  Rename Theme",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "New Theme Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=196, h,
    dlg.newThemeName,
    activate = dlg.activateFirstTextField,
    # TODO disallow invalid filename chars?
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if not utils.isValidFilename(dlg.newThemeName):
    validationError = "Theme name is invalid"

  var validationWarning = ""
  let idx = findThemeIndex(dlg.newThemeName, a)
  if idx.isSome:
    let theme = a.theme.themeNames[idx.get]
    if theme.userTheme:
      validationWarning = "A user theme with this name already exists"
    else:
      validationWarning = "Built-in theme will be shadowed by this name"

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationError(validationError),
              style=a.theme.errorLabelStyle)

  elif validationWarning != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationWarning(validationWarning),
              style=a.theme.warningLabelStyle)


  proc renameAction(dlg: RenameThemeDialogParams; a) =
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc renameTheme(a) =
      if renameTheme(a.currThemeName, newThemePath, a):
        buildThemeList(a)
        a.theme.nextThemeIndex = findThemeIndex(dlg.newThemeName, a)

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, action=renameTheme, a)
    else:
      renameTheme(a)

    closeDialog(a)



  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = validationError != "", style = a.theme.buttonStyle):
    renameAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): renameAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Delete theme dialog

proc openDeleteThemeDialog(a) =
  a.dialogs.activeDialog = dlgDeleteThemeDialog


proc deleteThemeDialog(a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(
    x, y, DlgWidth, h, "Are you sure you want to delete the theme?",
    style=a.theme.labelStyle
  )

  proc deleteAction(a) =
    if deleteTheme(a.currThemeName, a):
      buildThemeList(a)
      with a.theme:
        nextThemeIndex = min(currThemeIndex, themeNames.high).Natural.some

    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style = a.theme.buttonStyle):
    deleteAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel): cancelAction(a)
    elif ke.isShortcutDown(scAccept): deleteAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# }}}

# {{{ Undoable actions

# {{{ undoAction()
proc undoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canUndo:
    let drawTrail = a.opts.drawTrail
    a.opts.drawTrail = false

    let undoStateData = um.undo(a.doc.map)
    if a.doc.map.hasLevels:
      moveCursorTo(undoStateData.undoLocation, a)

    a.opts.drawTrail = drawTrail

    setStatusMessage(IconUndo, fmt"Undid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to undo", a=a)

# }}}
# {{{ redoAction()
proc redoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canRedo:
    let drawTrail = a.opts.drawTrail
    a.opts.drawTrail = false

    let undoStateData = um.redo(a.doc.map)
    moveCursorTo(undoStateData.location, a)

    a.opts.drawTrail = drawTrail

    setStatusMessage(IconRedo,
                     fmt"Redid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to redo", a=a)
# }}}

# {{{ setFloorAction()
proc setFloorAction(f: Floor; a) =
  let ot = a.doc.map.guessFloorOrientation(a.ui.cursor)
  actions.setOrientedFloor(a.doc.map, a.ui.cursor, f, ot, a.ui.currFloorColor,
                           a.doc.undoManager)
  setStatusMessage(fmt"Set floor type – {f}", a)

# }}}
# {{{ cycleFloorGroupAction()
proc cycleFloorGroupAction(floors: seq[Floor], forward: bool; a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    var i = floors.find(floor)
    if i > -1:
      if forward: inc(i) else: dec(i)
      floor = floors[floorMod(i, floors.len)]
    else:
      floor = if forward: floors[0] else: floors[^1]

    setFloorAction(floor, a)
  else:
    setWarningMessage("Cannot set floor type of an empty cell", a=a)

# }}}
# {{{ startExcavateTunnelAction()
proc startExcavateTunnelAction(a) =
  let cur = a.ui.cursor
  actions.excavateTunnel(a.doc.map, loc=cur, undoLoc=cur, a.ui.currFloorColor,
                         a.doc.undoManager, groupWithPrev=false)

  setStatusMessage(IconPencil, "Excavate tunnel", @[IconArrowsAll,
                   "excavate"], a)

# }}}
# {{{ startEraseCellsAction()
proc startEraseCellsAction(a) =
  let cur = a.ui.cursor
  actions.eraseCell(a.doc.map, loc=cur, undoLoc=cur, a.doc.undoManager)
  setStatusMessage(IconEraser, "Erase cell", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startEraseTrailAction()
proc startEraseTrailAction(a) =
  let cur = a.ui.cursor
  actions.eraseTrail(a.doc.map, loc=cur, undoLoc=cur, a.doc.undoManager)
  setStatusMessage(IconEraser, "Erase trail", @[IconArrowsAll, "erase"], a)

# }}}

# {{{ setDrawWallActionMessage()

proc mkRepeatWallActionString(name: string; a): string =
  let action = $a.ui.drawWallRepeatAction
  fmt"repeat {action} {name}"


proc doSetDrawWallActionMessage(name: string; a) =
  var commands = @[IconArrowsAll, "set/clear"]

  if a.ui.drawWallRepeatAction != dwaNone:
    commands.add("Shift")
    commands.add(mkRepeatWallActionString(name, a))

  setStatusMessage("", fmt"Draw {name}", commands, a)


proc setDrawWallActionMessage(a) =
  doSetDrawWallActionMessage(name = "wall", a)

# }}}
# {{{ setDrawWallActionRepeatMessage()
proc doSetDrawWallActionRepeatMessage(name: string, a) =
  let icon = if a.ui.drawWallRepeatDirection.orientation == Horiz:
               IconArrowsVert
             else:
               IconArrowsHoriz

  setStatusMessage("", fmt"Draw {name} repeat",
                   @[icon, mkRepeatWallActionString(name, a)], a)


proc setDrawWallActionRepeatMessage(a) =
  doSetDrawWallActionRepeatMessage(name = "wall", a)

# }}}
# {{{ setDrawSpecialWallActionMessage()
proc setDrawSpecialWallActionMessage(a) =
  doSetDrawWallActionMessage(name = "special wall", a)

# }}}
# {{{ setDrawSpecialWallActionRepeatMessage()
proc setDrawSpecialWallActionRepeatMessage(a) =
  doSetDrawWallActionRepeatMessage(name = "special wall", a)

# }}}

# }}}
# {{{ Non-undoable actions
# {{{ openUserManual()
proc openUserManual(a) =
  openDefaultBrowser(a.paths.manualDir / "index.html")

# }}}
# {{{ openWebsite()
proc openWebsite(a) =
  openDefaultBrowser("https://gridmonger.johnnovak.net")

# }}}
# {{{ openForum()
proc openForum(a) =
  openDefaultBrowser("https://gridmonger.johnnovak.net")

# }}}

# {{{ newMap()
proc newMap(a) =
  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(action=openNewMapDialog, a)
  else:
    openNewMapDialog(a)

# }}}
# {{{ openMap()
proc openMap(a) =

  proc doOpenMap(a) =
    when defined(DEBUG): discard
    else:
      let filename = fileDialog(fdOpenFile,
                                filters=GridmongerMapFileFilter)
      if filename != "":
        discard loadMap(filename, a)

  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(action=doOpenMap, a)
  else:
    doOpenMap(a)


when defined(windows):

  proc openMap(filename: string; a) =
    proc doOpenMap(a) =
      discard loadMap(filename, a)

    if a.doc.undoManager.isModified:
      openSaveDiscardMapDialog(action=doOpenMap, a)
    else:
      doOpenMap(a)

# }}}
# {{{ saveMapAs()
proc saveMapAs(a) =
  when not defined(DEBUG):
    var filename = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if filename != "":
      filename = addFileExt(filename, MapFileExt)

      saveMap(filename, autosave=false, createBackup=false, a)
      a.doc.filename = filename

# }}}
# {{{ saveMap()
proc saveMap(a) =
  if a.doc.filename != "":
    saveMap(a.doc.filename, autosave=false, createBackup=true, a)
  else:
    saveMapAs(a)

# }}}

# {{{ reloadTheme()
proc reloadTheme(a) =

  proc doReloadTheme(a) =
    a.theme.nextThemeIndex = a.theme.currThemeIndex.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(action=doReloadTheme, a)
  else:
    doReloadTheme(a)

# }}}
# {{{ selectPrevTheme()
proc selectPrevTheme(a) =

  proc prevTheme(a) =
    var i = a.theme.currThemeIndex
    if i == 0: i = a.theme.themeNames.high else: dec(i)
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(action=prevTheme, a)
  else:
    prevTheme(a)

# }}}
# {{{ selectNextTheme()
proc selectNextTheme(a) =

  proc nextTheme(a) =
    var i = a.theme.currThemeIndex
    inc(i)
    if i > a.theme.themeNames.high: i = 0
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(action=nextTheme, a)
  else:
    nextTheme(a)

# }}}

# {{{ selectPrevLevel()
proc selectPrevLevel(a) =
  var si = currSortedLevelIdx(a)
  if si > 0:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si - 1]
    setCursor(cur, a)

# }}}
# {{{ selectNextLevel()
proc selectNextLevel(a) =
  var si = currSortedLevelIdx(a)
  if si < a.doc.map.levels.len-1:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si + 1]
    setCursor(cur, a)

# }}}

# {{{ centerCursorAfterZoom()
proc centerCursorAfterZoom(a) =
  alias(dp, a.ui.drawLevelParams)
  let cur = a.ui.cursor

  let viewCol = round(a.ui.prevCursorViewX / dp.gridSize).int
  let viewRow = round(a.ui.prevCursorViewY / dp.gridSize).int
  dp.viewStartCol = max(cur.col - viewCol, 0)
  dp.viewStartRow = max(cur.row - viewRow, 0)

# }}}
# {{{ zoomIn()
proc zoomIn(a) =
  incZoomLevel(a.theme.levelStyle, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}
# {{{ zoomOut()
proc zoomOut(a) =
  decZoomLevel(a.theme.levelStyle, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}

# {{{ selectSpecialWall()
proc selectSpecialWall(index: Natural; a) =
  assert index <= SpecialWalls.high
  a.ui.currSpecialWall = index

# }}}

# {{{ selectPrevFloorColor()
proc selectPrevFloorColor(a) =
  if a.ui.currFloorColor > 0: dec(a.ui.currFloorColor)
  else: a.ui.currFloorColor = a.theme.levelStyle.floorBackgroundColor.high

# }}}
# {{{ selectNextFloorColor()
proc selectNextFloorColor(a) =
  if a.ui.currFloorColor < a.theme.levelStyle.floorBackgroundColor.high:
    inc(a.ui.currFloorColor)
  else: a.ui.currFloorColor = 0

# }}}
# {{{ pickFloorColor()
proc pickFloorColor(a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    a.ui.currFloorColor = a.doc.map.getFloorColor(a.ui.cursor)
    setStatusMessage(NoIcon, "Picked floor colour", a)
  else:
    setWarningMessage("Cannot pick floor colour of an empty cell", a=a)

# }}}
# {{{ selectFloorColor()
proc selectFloorColor(index: Natural; a) =
  assert index <= LevelStyle.floorBackgroundColor.high
  a.ui.currFloorColor = index

# }}}

# }}}
# {{{ Event handling

# {{{ resetManualNoteTooltip()
proc resetManualNoteTooltip(a) =
  with a.ui.manualNoteTooltipState:
    show = false
    mx = -1
    my = -1

# }}}

# {{{ enterDrawWallMode()
proc enterDrawWallMode(specialWall: bool; a) =
  a.ui.editMode = if specialWall: emDrawSpecialWall else: emDrawWall
  a.ui.drawWallRepeatAction = dwaNone

  if specialWall:
    setDrawSpecialWallActionMessage(a)
  else:
    setDrawWallActionMessage(a)

# }}}
# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents(a) =
  alias(ui, a.ui)

  proc moveCursorToMousePos(a) =
    let loc = locationAtMouse(a)
    if loc.isSome:
      a.ui.cursor = loc.get
      resetManualNoteTooltip(a)

  if a.opts.wasdMode:
    if ui.editMode == emNormal:
      if koi.mbLeftDown():
        if ui.mouseCanStartExcavateAction:
          if koi.shiftDown():
            moveCursorToMousePos(a)
          else:
            ui.editMode = emExcavateTunnel
            startExcavateTunnelAction(a)
      else:
        ui.mouseCanStartExcavateAction = true

      if koi.mbRightDown():
        enterDrawWallMode(specialWall = false, a)

      elif koi.mbMiddleDown():
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

    elif ui.editMode == emExcavateTunnel:
      if not koi.mbLeftDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    elif ui.editMode == emDrawWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)
      else:
        if koi.mbLeftDown():
          enterDrawWallMode(specialWall = true, a)

    elif ui.editMode == emDrawWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    elif ui.editMode == emDrawSpecialWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavateAction = false
        clearStatusMessage(a)
      else:
        if not koi.mbLeftDown():
          enterDrawWallMode(specialWall = false, a)

    elif ui.editMode == emDrawSpecialWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavateAction = false
        clearStatusMessage(a)

    elif ui.editMode == emEraseCell:
      if not koi.mbMiddleDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

  else:  # not WASD mode
    if koi.mbLeftDown():
      moveCursorToMousePos(a)

# }}}
# {{{ handleGlobalKeyEvents()

template toggleOption(opt: untyped, icon, msg, on, off: string; a) =
  opt = not opt
  let state = if opt: on else: off
  setStatusMessage(icon, msg & " " & state, a)

template toggleShowOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="shown", off="hidden", a)

template toggleOnOffOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="on", off="off", a)

proc toggleThemeEditor(a) =
  toggleShowOption(a.opts.showThemeEditor, NoIcon, "Theme editor pane", a)

proc showQuickReference(a) =
  a.opts.showQuickReference = true
  setStatusMessage(IconQuestion, "Quick keyboard reference",
                   @[fmt"Ctrl+{IconArrowsHoriz}", "switch tab",
                     "Esc/Space/Enter", "exit",
                     "F1", "open user manual"], a)

proc toggleTitleBar(a) =
  toggleShowOption(a.win.showTitleBar, NoIcon, "Title bar", a)

# TODO separate into level events and global events?
proc handleGlobalKeyEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)
  alias(opts, a.opts)
  alias(dp, a.ui.drawLevelParams)

  var l = currLevel(a)

  proc turnLeft(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) - 1, ord(CardinalDir.high) + 1))

  proc turnRight(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) + 1, ord(CardinalDir.high) + 1))

  template backward(): auto = turnLeft(turnLeft(ui.cursorOrient))
  template left():     auto = turnLeft(ui.cursorOrient)
  template right():    auto = turnRight(ui.cursorOrient)

  proc handleMoveWalk(ke: Event; a) =
    const mkS = {mkShift}

    var s = 1
    if mkCtrl in ke.mods:
      if ke.key in AllWasdMoveKeys: return
      else: s = CursorJump

    var ke = ke
    ke.mods = ke.mods - {mkCtrl}

    let k = if opts.wasdMode: WalkKeysWasd else: WalkKeysCursor

    if   ke.isKeyDown(k.turnLeft,    repeat=true): ui.cursorOrient = left()
    elif ke.isKeyDown(k.turnRight,   repeat=true): ui.cursorOrient = right()
    elif ke.isKeyDown(k.forward,     repeat=true): moveCursor(ui.cursorOrient, s, a)
    elif ke.isKeyDown(k.backward,    repeat=true): moveCursor(backward(), s, a)
    elif ke.isKeyDown(k.strafeLeft,  repeat=true): moveCursor(left(), s, a)
    elif ke.isKeyDown(k.strafeRight, repeat=true): moveCursor(right(), s, a)

    elif ke.isKeyDown(k.turnLeft,    mkS, repeat=true): ui.cursorOrient = left()
    elif ke.isKeyDown(k.turnRight,   mkS, repeat=true): ui.cursorOrient = right()
    elif ke.isKeyDown(k.strafeLeft,  mkS, repeat=true): moveLevel(left(), s, a)
    elif ke.isKeyDown(k.strafeRight, mkS, repeat=true): moveLevel(right(), s, a)
    elif ke.isKeyDown(k.forward,     mkS, repeat=true): moveLevel(ui.cursorOrient, s, a)
    elif ke.isKeyDown(k.backward,    mkS, repeat=true): moveLevel(backward(), s, a)


  template handleMoveKeys(ke: Event, allowWasdKeys, allowRepeat: bool,
                          moveHandler: untyped) =
    let k = if allowWasdKeys and opts.wasdMode: MoveKeysWasd
            else: MoveKeysCursor

    if   ke.isKeyDown(k.left,  repeat=allowRepeat): moveHandler(dirW, a)
    elif ke.isKeyDown(k.right, repeat=allowRepeat): moveHandler(dirE, a)
    elif ke.isKeyDown(k.up,    repeat=allowRepeat): moveHandler(dirN, a)
    elif ke.isKeyDown(k.down,  repeat=allowRepeat): moveHandler(dirS, a)


  proc handleMoveCursor(ke: Event; allowPan, allowJump, allowWasdKeys: bool;
                        a): bool =

    let k = if allowWasdKeys and opts.wasdMode: MoveKeysWasd
            else: MoveKeysCursor

    var s = 1
    if allowJump and mkCtrl in ke.mods:
      if ke.key in AllWasdMoveKeys: return
      else: s = CursorJump

    var ke = ke
    ke.mods = ke.mods - {mkCtrl}

    result = true

    if   ke.isKeyDown(k.left,  repeat=true): moveCursor(dirW, s, a)
    elif ke.isKeyDown(k.right, repeat=true): moveCursor(dirE, s, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveCursor(dirN, s, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveCursor(dirS, s, a)
    elif allowPan:
      if   ke.isKeyDown(k.left,  {mkShift}, repeat=true): moveLevel(dirW, s, a)
      elif ke.isKeyDown(k.right, {mkShift}, repeat=true): moveLevel(dirE, s, a)
      elif ke.isKeyDown(k.up,    {mkShift}, repeat=true): moveLevel(dirN, s, a)
      elif ke.isKeyDown(k.down,  {mkShift}, repeat=true): moveLevel(dirS, s, a)

    result = false


  proc drawWallRepeatMoveKeyHandler(dir: CardinalDir; a) =
    let cur = ui.cursor
    let drawDir = ui.drawWallRepeatDirection

    if dir.orientation == drawDir.orientation.opposite:
      let newCur = stepCursor(cur, dir, steps=1, a)
      if newCur != cur:
        if map.canSetWall(newCur, drawDir):
          setCursor(newCur, a)

          actions.setWall(map, newCur, drawDir, ui.drawWallRepeatWall, um)
          setDrawWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)
    else:
      setWarningMessage(
        fmt"Can only repeat in {dir.orientation.opposite} direction",
        keepStatusMessage=true, a=a
      )


  if hasKeyEvent():
    let ke = koi.currEvent()
    # TODO eventHandled is not set here, but it's not actually needed (yet)

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # TODO revisit tooltip reset logic
      # Reset tooltip display on certain keypresses only
      if not (ke.key == keySpace) and
         not (ke.action == kaUp) and
         not (ke.key in {keyLeftControl,  keyLeftShift,  keyLeftAlt,
                         keyRightControl, keyRightShift, keyRightAlt}):
        resetManualNoteTooltip(a)

      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        if handleMoveCursor(ke, allowPan=true, allowJump=true,
                            allowWasdKeys=true, a):
          setStatusMessage("moved", a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true): selectNextLevel(a)

      let cur = ui.cursor

      if not opts.wasdMode and ke.isShortcutDown(scExcavateTunnel):
        ui.editMode = emExcavateTunnel
        startExcavateTunnelAction(a)

      elif not (opts.wasdMode and opts.walkMode) and
           ke.isShortcutDown(scEraseCell):
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

      elif ke.isShortcutDown(scDrawClearFloor):
        ui.editMode = emDrawClearFloor
        setStatusMessage(IconEraser, "Draw/clear floor",
                         @[IconArrowsAll, "draw/clear"], a)

        actions.drawClearFloor(map, loc=cur, undoLoc=cur,
                               ui.currFloorColor, um)

      elif ke.isShortcutDown(scToggleFloorOrientation):
        let floor = map.getFloor(cur)

        if floor != fEmpty:
          actions.toggleFloorOrientation(map, cur, um)
          if map.getFloorOrientation(cur) == Horiz:
            setStatusMessage(IconArrowsHoriz,
                             "Floor orientation set to horizontal", a)
          else:
            setStatusMessage(IconArrowsVert,
                             "Floor orientation set to vertical", a)
        else:
          setWarningMessage("Cannot set floor orientation of an empty cell",
                            a=a)

      elif ke.isShortcutDown(scSetFloorColor):
        ui.editMode = emColorFloor
        setStatusMessage(IconEraser, "Set floor colour",
                         @[IconArrowsAll, "set colour"], a)

        if not map.isEmpty(cur):
          actions.setFloorColor(map, loc=cur, undoLoc=cur,
                                ui.currFloorColor, um)

      elif not opts.wasdMode and ke.isShortcutDown(scDrawWall):
        enterDrawWallMode(specialWall = false, a)

      elif ke.isShortcutDown(scDrawSpecialWall):
        enterDrawWallMode(specialWall = true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Forward):
        cycleFloorGroupAction(FloorGroup1, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Forward):
        cycleFloorGroupAction(FloorGroup2, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Forward):
        cycleFloorGroupAction(FloorGroup3, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Forward):
        cycleFloorGroupAction(FloorGroup4, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Forward):
        cycleFloorGroupAction(FloorGroup5, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Forward):
        cycleFloorGroupAction(FloorGroup6, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Forward):
        cycleFloorGroupAction(FloorGroup7, forward=true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Backward):
        cycleFloorGroupAction(FloorGroup1, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Backward):
        cycleFloorGroupAction(FloorGroup2, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Backward):
        cycleFloorGroupAction(FloorGroup3, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Backward):
        cycleFloorGroupAction(FloorGroup4, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Backward):
        cycleFloorGroupAction(FloorGroup5, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Backward):
        cycleFloorGroupAction(FloorGroup6, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Backward):
        cycleFloorGroupAction(FloorGroup7, forward=false, a)

      elif ke.isShortcutDown(scSelectSpecialWall1):  selectSpecialWall(0, a)
      elif ke.isShortcutDown(scSelectSpecialWall2):  selectSpecialWall(1, a)
      elif ke.isShortcutDown(scSelectSpecialWall3):  selectSpecialWall(2, a)
      elif ke.isShortcutDown(scSelectSpecialWall4):  selectSpecialWall(3, a)
      elif ke.isShortcutDown(scSelectSpecialWall5):  selectSpecialWall(4, a)
      elif ke.isShortcutDown(scSelectSpecialWall6):  selectSpecialWall(5, a)
      elif ke.isShortcutDown(scSelectSpecialWall7):  selectSpecialWall(6, a)
      elif ke.isShortcutDown(scSelectSpecialWall8):  selectSpecialWall(7, a)
      elif ke.isShortcutDown(scSelectSpecialWall9):  selectSpecialWall(8, a)
      elif ke.isShortcutDown(scSelectSpecialWall10): selectSpecialWall(9, a)
      elif ke.isShortcutDown(scSelectSpecialWall11): selectSpecialWall(10, a)
      elif ke.isShortcutDown(scSelectSpecialWall12): selectSpecialWall(11, a)

      elif ke.isShortcutDown(scPreviousSpecialWall, repeat=true):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isShortcutDown(scNextSpecialWall, repeat=true):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isShortcutDown(scEraseTrail):
        if not opts.drawTrail:
          ui.editMode = emEraseTrail
          startEraseTrailAction(a)
        else:
          setWarningMessage("Cannot erase trail when draw trail is on", a=a)

      elif ke.isShortcutDown(scExcavateTrail):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.excavateTrail(map, cur, bbox.get, ui.currFloorColor, um)
          actions.clearTrailInLevel(map, cur, bbox.get, um, groupWithPrev=true,
                                    actionName="Excavate trail in level")

          setStatusMessage(IconPencil, "Trail excavated in level", a)
        else:
          setWarningMessage("No trail to excavate", a=a)

      elif ke.isShortcutDown(scClearTrail):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.clearTrailInLevel(map, cur, bbox.get, um)
          setStatusMessage(IconEraser, "Cleared trail in level", a)
        else:
          setWarningMessage("No trail to clear", a=a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor): pickFloorColor(a)

      elif ke.isShortcutDown(scSelectFloorColor1):  selectFloorColor(0, a)
      elif ke.isShortcutDown(scSelectFloorColor2):  selectFloorColor(1, a)
      elif ke.isShortcutDown(scSelectFloorColor3):  selectFloorColor(2, a)
      elif ke.isShortcutDown(scSelectFloorColor4):  selectFloorColor(3, a)
      elif ke.isShortcutDown(scSelectFloorColor5):  selectFloorColor(4, a)
      elif ke.isShortcutDown(scSelectFloorColor6):  selectFloorColor(5, a)
      elif ke.isShortcutDown(scSelectFloorColor7):  selectFloorColor(6, a)
      elif ke.isShortcutDown(scSelectFloorColor8):  selectFloorColor(7, a)
      elif ke.isShortcutDown(scSelectFloorColor9):  selectFloorColor(8, a)
      elif ke.isShortcutDown(scSelectFloorColor10): selectFloorColor(9, a)

      elif ke.isShortcutDown(scUndo, repeat=true): undoAction(a)
      elif ke.isShortcutDown(scRedo, repeat=true): redoAction(a)

      elif ke.isShortcutDown(scMarkSelection):
        enterSelectMode(a)

      elif ke.isShortcutDown(scPaste):
        if ui.copyBuf.isSome:
          actions.pasteSelection(map, cur, ui.copyBuf.get,
                                 pasteBufferLevelIndex=CopyBufferLevelIndex,
                                 undoLoc=cur, um)
          if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

          setStatusMessage(IconPaste, "Buffer pasted", a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scPastePreview):
        if ui.copyBuf.isSome:
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          opts.drawTrail = false
          ui.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "paste", "Esc", "cancel"], a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scNudgePreview):
        let sel = newSelection(l.rows, l.cols)
        sel.fill(true)
        ui.nudgeBuf = SelectionBuffer(level: l, selection: sel).some
        map.levels[cur.level] = newLevel(
          l.locationName, l.levelName, l.elevation,
          l.rows, l.cols,
          l.overrideCoordOpts, l.coordOpts,
          l.regionOpts
        )

        dp.selStartRow = 0
        dp.selStartCol = 0

        ui.editMode = emNudgePreview
        opts.drawTrail = false
        setStatusMessage(IconArrowsAll, "Nudge preview",
                         @[IconArrowsAll, "nudge",
                         "Enter", "confirm", "Esc", "cancel"], a)


      elif ke.isShortcutDown(scJumpToLinkedCell):
        let otherLoc = map.getLinkedLocation(cur)
        if otherLoc.isSome:
          moveCursorTo(otherLoc.get, a)
        else:
          setWarningMessage("Not a linked cell", a=a)

      elif ke.isShortcutDown(scLinkCell):
        let floor = map.getFloor(cur)
        if floor in LinkSources:
          ui.linkSrcLocation = cur
          ui.editMode = emSetCellLink
          setSetLinkDestinationMessage(floor, a)
        else:
          setWarningMessage("Cannot link current cell", a=a)

      elif ke.isShortcutDown(scZoomIn, repeat=true):
        zoomIn(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isShortcutDown(scZoomOut, repeat=true):
        zoomOut(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isShortcutDown(scEditNote):
        if map.isEmpty(cur):
          setWarningMessage("Cannot attach note to empty cell", a=a)
        else:
          openEditNoteDialog(a)

      elif ke.isShortcutDown(scEraseNote):
        if map.hasNote(cur):
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)
        else:
          setWarningMessage("No note to erase in cell", a=a)

      elif ke.isShortcutDown(scEditLabel):
        openEditLabelDialog(a)

      elif ke.isShortcutDown(scEraseLabel):
        if map.hasLabel(cur):
          actions.eraseLabel(map, cur, um)
          setStatusMessage(IconEraser, "Label erased", a)
        else:
          setWarningMessage("No label to erase in cell", a=a)

      elif ke.isShortcutDown(scShowNoteTooltip):
        if ui.manualNoteTooltipState.show:
          resetManualNoteTooltip(a)
        else:
          if map.hasNote(cur):
            with ui.manualNoteTooltipState:
              show = true
              location = cur
              mx = koi.mx()
              my = koi.my()

      elif ke.isShortcutDown(scEditPreferences): openPreferencesDialog(a)

      elif ke.isShortcutDown(scNewLevel):
        if map.levels.len < NumLevelsLimits.maxInt:
          openNewLevelDialog(a)
        else:
          setWarningMessage(
            "Cannot add new level: maximum number of levels has been reached " &
            fmt"({NumLevelsLimits.maxInt})", a=a
          )

      elif ke.isShortcutDown(scDeleteLevel):
        openDeleteLevelDialog(a)

      elif ke.isShortcutDown(scNewMap): newMap(a)
      elif ke.isShortcutDown(scEditMapProps): openEditMapPropsDialog(a)

      elif ke.isShortcutDown(scEditLevelProps):
        openEditLevelPropsDialog(a)

      elif ke.isShortcutDown(scResizeLevel):
        openResizeLevelDialog(a)

      elif ke.isShortcutDown(scEditRegionProps):
        if l.regionOpts.enabled:
          openEditRegionPropertiesDialog(a)
        else:
          setWarningMessage(
            "Cannot edit region properties: regions are not enabled for level",
            a=a
          )

      elif ke.isShortcutDown(scOpenMap):       openMap(a)
      elif ke.isShortcutDown(scSaveMap):       saveMap(a)
      elif ke.isShortcutDown(scSaveMapAs):     saveMapAs(a)

      elif ke.isShortcutDown(scReloadTheme):   reloadTheme(a)
      elif ke.isShortcutDown(scPreviousTheme): selectPrevTheme(a)
      elif ke.isShortcutDown(scNextTheme):     selectNextTheme(a)

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

      elif ke.isShortcutDown(scShowAboutDialog):
        openAboutDialog(a)

      elif ke.isShortcutDown(scToggleThemeEditor):
        toggleThemeEditor(a)

      elif ke.isShortcutDown(scToggleQuickReference):
        showQuickReference(a)

      # Toggle options
      elif ke.isShortcutDown(scToggleCellCoords):
        toggleShowOption(dp.drawCellCoords, NoIcon, "Cell coordinates", a)

      elif ke.isShortcutDown(scToggleNotesPane):
        toggleShowOption(opts.showNotesPane, NoIcon, "Notes pane", a)

      elif ke.isShortcutDown(scToggleToolsPane):
        toggleShowOption(opts.showToolsPane, NoIcon, "Tools pane", a)

      elif ke.isShortcutDown(scToggleWalkMode):
        opts.walkMode = not opts.walkMode
        let msg = if opts.walkMode: "Walk mode" else: "Normal mode"
        setStatusMessage(msg, a)

      elif ke.isShortcutDown(scToggleWasdMode):
        toggleOnOffOption(opts.wasdMode, IconMouse, "WASD mode", a)

      elif ke.isShortcutDown(scToggleDrawTrail):
        if not opts.drawTrail:
          actions.drawTrail(map, loc=cur, undoLoc=cur, um)
        toggleOnOffOption(opts.drawTrail, IconShoePrints, "Draw trail", a)

      elif ke.isShortcutDown(scToggleTitleBar):
        toggleTitleBar(a)

    # }}}
    # {{{ emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor
    of emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                                 allowWasdKeys=true, a)
      let cur = ui.cursor

      if cur != ui.prevCursor:
        if   ui.editMode == emExcavateTunnel:
          actions.excavateTunnel(map, loc=cur, undoLoc=ui.prevCursor,
                                 ui.currFloorColor,
                                 um, groupWithPrev=opts.drawTrail)

        elif ui.editMode == emEraseCell:
          actions.eraseCell(map, loc=cur, undoLoc=ui.prevCursor, um)

        elif ui.editMode == emEraseTrail:
          actions.eraseTrail(map, loc=cur, undoLoc=cur, um)

        elif ui.editMode == emDrawClearFloor:
          actions.drawClearFloor(map, loc=cur, undoLoc=ui.prevCursor,
                                 ui.currFloorColor, um)

        elif ui.editMode == emColorFloor:
          if not map.isEmpty(cur):
            actions.setFloorColor(map, loc=cur, undoLoc=ui.prevCursor,
                                  ui.currFloorColor, um)

      if ke.isShortcutUp(scExcavateTunnel):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isShortcutUp({scEraseCell, scDrawClearFloor, scEraseTrail,
                          scSetFloorColor}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir; a) =
        let cur = ui.cursor

        if map.canSetWall(cur, dir):
          let w = if map.getWall(cur, dir) == wWall: wNone
                  else: wWall

          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, cur, dir, w, um)
          setDrawWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false, handleMoveKey)

      if not opts.wasdMode and ke.isShortcutUp(scDrawWall):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawWallRepeat
          setDrawWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat):
        setDrawWallActionMessage(a)

    # }}}
    # {{{ emDrawWallRepeat
    of emDrawWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat):
        ui.editMode = emDrawWall
        setDrawWallActionMessage(a)

      if not opts.wasdMode and ke.isShortcutUp(scDrawWall):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawSpecialWall
    of emDrawSpecialWall:
      proc handleMoveKey(dir: CardinalDir; a) =
        let cur = ui.cursor

        if map.canSetWall(cur, dir):
          var curSpecWall = SpecialWalls[ui.currSpecialWall]

          if   curSpecWall == wOneWayDoorNE:
            if dir in {dirS, dirW}: curSpecWall = wOneWayDoorSW
          elif curSpecWall == wLeverSW:
            if dir in {dirN, dirE}: curSpecWall = wLeverNE
          elif curSpecWall == wNicheSW:
            if dir in {dirN, dirE}: curSpecWall = wNicheNE
          elif curSpecWall == wStatueSw:
            if dir in {dirN, dirE}: curSpecWall = wStatueNE
          elif curSpecWall == wWritingSW:
            if dir in {dirN, dirE}: curSpecWall = wWritingNE

          let w = if map.getWall(cur, dir) == curSpecWall: wNone
                  else: curSpecWall
 
          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, cur, dir, w, um)
          setDrawSpecialWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false, handleMoveKey)

      if ke.isShortcutUp(scDrawSpecialWall):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawSpecialWallRepeat
          setDrawSpecialWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat):
        setDrawSpecialWallActionMessage(a)

    # }}}
    # {{{ emDrawSpecialWallRepeat
    of emDrawSpecialWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat):
        ui.editMode = emDrawSpecialWall
        setDrawSpecialWallActionMessage(a)

      if ke.isShortcutUp(scDrawSpecialWall):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, a)
      let cur = ui.cursor

      if   koi.ctrlDown(): setSelectModeActionMessage(a)
      else:                setSelectModeSelectMessage(a)

      if   ke.isShortcutDown(scSelectionDraw):
        ui.selection.get[cur.row, cur.col] = true
        ui.editMode = emSelectDraw

      elif ke.isShortcutDown(scSelectionErase):
        ui.selection.get[cur.row, cur.col] = false
        ui.editMode = emSelectErase

      elif ke.isShortcutDown(scSelectionAll):  ui.selection.get.fill(true)
      elif ke.isShortcutDown(scSelectionNone): ui.selection.get.fill(false)

      elif ke.isShortcutDown({scSelectionAddRect, scSelectionSubRect}):
        ui.editMode = emSelectRect
        ui.selRect = some(SelectionRect(
          startRow: cur.row,
          startCol: cur.col,
          rect: rectN(cur.row, cur.col, cur.row+1, cur.col+1),
          selected: ke.isShortcutDown(scSelectionAddRect)
        ))

      elif ke.isShortcutDown(scSelectionCopy):
        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isShortcutDown(scSelectionCut):
        let selection = ui.selection.get

        # delete links from a previous cut to buffer operation if it hasn't
        # been pasted yet
        map.deleteLinksFromOrToLevel(CopyBufferLevelIndex)

        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            level: cur.level,
            col: bbox.c1,
            row: bbox.r1
          )
          actions.cutSelection(map, bboxTopLeft, bbox, selection,
                               linkDestLevelIndex=CopyBufferLevelIndex, um)
          ui.cutToBuffer = true

          exitSelectMode(a)

          var cur = cur
          cur.row = bbox.r1
          cur.col = bbox.c1
          setCursor(cur, a)

          setStatusMessage(IconCut, "Cut selection to buffer", a)

      elif ke.isShortcutDown(scSelectionMove):
        let selection = ui.selection.get
        let bbox = copySelection(ui.nudgeBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            level: cur.level,
            col: bbox.c1,
            row: bbox.r1
          )
          ui.moveUndoLocation = bboxTopLeft

          actions.cutSelection(map, bboxTopLeft, bbox, selection,
                               linkDestLevelIndex=MoveBufferLevelIndex, um)
          exitSelectMode(a)

          # Enter paste preview mode
          var cur = cur
          cur.row = bbox.r1
          cur.col = bbox.c1
          setCursor(cur, a)

          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          ui.editMode = emMovePreview
          setStatusMessage(IconTiles, "Move selection",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "confirm", "Esc", "cancel"], a)

      elif ke.isShortcutDown(scSelectionEraseArea):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.eraseSelection(map, cur.level, selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isShortcutDown(scSelectionFillArea):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.fillSelection(map, cur.level, selection, bbox.get,
                                ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Filled selection", a)

      elif ke.isShortcutDown(scSelectionSurroundArea):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.surroundSelectionWithWalls(map, cur.level, selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isShortcutDown(scSelectionSetFloorColorArea):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.setSelectionFloorColor(map, cur.level, selection,
                                         bbox.get, ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Set floor colour of selection", a)

      elif ke.isShortcutDown(scSelectionCropArea):
        let sel = ui.selection.get
        let bbox = sel.boundingBox
        if bbox.isSome:
          let newCur = actions.cropLevel(map, cur, bbox.get, um)
          moveCursorTo(newCur, a)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Cropped level to selection", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true): zoomOut(a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor): pickFloorColor(a)

      elif ke.isShortcutDown(scCancel):
        exitSelectMode(a)
        a.clearStatusMessage()

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

    # }}}
    # {{{ emSelectDraw, emSelectErase
    of emSelectDraw, emSelectErase:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, a)
      let cur = ui.cursor
      ui.selection.get[cur.row, cur.col] = ui.editMode == emSelectDraw

      if ke.isShortcutUp({scSelectionDraw, scSelectionErase}):
        ui.editMode = emSelect

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, a)
      let cur = ui.cursor

      var r1,c1, r2,c2: Natural
      if ui.selRect.get.startRow <= cur.row:
        r1 = ui.selRect.get.startRow
        r2 = cur.row+1
      else:
        r1 = cur.row
        r2 = ui.selRect.get.startRow + 1

      if ui.selRect.get.startCol <= cur.col:
        c1 = ui.selRect.get.startCol
        c2 = cur.col+1
      else:
        c1 = cur.col
        c2 = ui.selRect.get.startCol + 1

      ui.selRect.get.rect = rectN(r1,c1, r2,c2)

      if ke.isShortcutUp({scSelectionAddRect, scSelectionSubRect}):
        ui.selection.get.fill(ui.selRect.get.rect, ui.selRect.get.selected)
        ui.selRect = SelectionRect.none
        ui.editMode = emSelect

    # }}}
    # {{{ emPastePreview
    of emPastePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scPasteAccept):
        actions.pasteSelection(map, cur, ui.copyBuf.get,
                               pasteBufferLevelIndex=CopyBufferLevelIndex,
                               undoLoc=cur, um, pasteTrail=true)

        if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true): zoomOut(a)

      elif ke.isShortcutDown(scCancel):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

    # }}}
    # {{{ emMovePreview
    of emMovePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scPasteAccept):
        actions.pasteSelection(map, cur, ui.nudgeBuf.get,
                               pasteBufferLevelIndex=MoveBufferLevelIndex,
                               undoLoc=ui.moveUndoLocation, um,
                               groupWithPrev=true, actionName="Move selection")

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Moved selection", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true): zoomOut(a)

      elif ke.isShortcutDown(scCancel):
        exitMovePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      # TODO add ctrl-jump support
      handleMoveKeys(ke, allowWasdKeys=false, allowRepeat=true, moveSelStart)

      let cur = ui.cursor

      if   ke.isShortcutDown(scZoomIn,  repeat=true): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true): zoomOut(a)

      elif ke.isShortcutDown(scAccept):
        let newCur = actions.nudgeLevel(map, cur,
                                        dp.selStartRow, dp.selStartCol,
                                        ui.nudgeBuf.get, um)
        moveCursorTo(newCur, a)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isShortcutDown(scCancel):
        exitNudgePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

    # }}}
    # {{{ emSetCellLink
    of emSetCellLink:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                                 allowWasdKeys=true, a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true): selectNextLevel(a)

      let cur = ui.cursor

      if cur != ui.prevCursor:
        let floor = map.getFloor(ui.linkSrcLocation)
        setSetLinkDestinationMessage(floor, a)

      if ke.isShortcutDown(scAccept):
        if map.isEmpty(cur):
          setWarningMessage("Cannot set link destination to an empty cell",
                            keepStatusMessage=true, a=a)

        elif cur == ui.linkSrcLocation:
          setWarningMessage("Cannot set link destination to the source cell",
                            keepStatusMessage=true, a=a)
        else:
          actions.setLink(map, src=ui.linkSrcLocation, dest=cur,
                          ui.currFloorColor, um)

          ui.editMode = emNormal

          let linkType = linkFloorToString(map.getFloor(cur))
          setStatusMessage(IconLink,
                           fmt"{capitalizeAscii(linkType)} link destination set",
                           a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true): zoomOut(a)

      elif ke.isShortcutDown(scCancel):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual):
        openUserManual(a)

    # }}}

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  if hasKeyEvent():
    let ke = koi.currEvent()

    if   ke.isShortcutDown(scNewMap):            newMap(a)
    elif ke.isShortcutDown(scEditMapProps):      openEditMapPropsDialog(a)

    elif ke.isShortcutDown(scOpenMap):           openMap(a)
    elif ke.isShortcutDown(scSaveMap):           saveMap(a)
    elif ke.isShortcutDown(scSaveMapAs):         saveMapAs(a)

    elif ke.isShortcutDown(scNewLevel):          openNewLevelDialog(a)

    elif ke.isShortcutDown(scReloadTheme):       reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme):     selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme):         selectNextTheme(a)

    elif ke.isShortcutDown(scEditPreferences):   openPreferencesDialog(a)

    elif ke.isShortcutDown(scUndo, repeat=true): undoAction(a)
    elif ke.isShortcutDown(scRedo, repeat=true): redoAction(a)

    elif ke.isShortcutDown(scOpenUserManual):    openUserManual(a)
    elif ke.isShortcutDown(scShowAboutDialog):   openAboutDialog(a)

    elif ke.isShortcutDown(scToggleThemeEditor):
      toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference):
      showQuickReference(a)

    # Toggle options
    elif ke.isShortcutDown(scToggleTitleBar):
      toggleTitleBar(a)

# }}}
# {{{ handleQuickRefKeyEvents()

let g_quickRefTabLabels = @["General", "Editing", "Dialogs"]

proc handleQuickRefKeyEvents(a) =
  if hasKeyEvent():
    let ke = koi.currEvent()

    a.quickRef.activeTab = handleTabNavigation(ke, a.quickRef.activeTab,
                                               g_quickRefTabLabels.high)

    if   ke.isShortcutDown(scReloadTheme):   reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme): selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme):     selectNextTheme(a)

    elif ke.isShortcutDown(scOpenUserManual):    openUserManual(a)
    elif ke.isShortcutDown(scToggleThemeEditor): toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference) or
         ke.isShortcutDown(scAccept) or
         ke.isShortcutDown(scCancel) or
         isKeyDown(keySpace):

      a.opts.showQuickReference = false
      clearStatusMessage(a)

# }}}

# }}}

# }}}
# {{{ Rendering

# {{{ renderNoteTooltip()
proc renderNoteTooltip(x, y: float, note: Annotation, a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(dp, a.ui.drawLevelParams)
  alias(ls, a.theme.levelStyle)

  if note.text != "":
    const PadX = 10
    const PadY = 8

    var
      noteBoxX = x
      noteBoxY = y
      noteBoxW = 250.0
      textX = noteBoxX + PadX
      textY = noteBoxY + PadY

    vg.setFont(14, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.5)

    let
      breakWidth = noteBoxW - PadX*2
      bounds = vg.textBoxBounds(textX, textY, breakWidth, note.text)

      noteTextH = bounds.y2 - bounds.y1
      noteTextW = bounds.x2 - bounds.x1
      noteBoxH = noteTextH + PadY*2

    noteBoxW = noteTextW + PadX*2

    let
      xOver = noteBoxX + noteBoxW - (dp.startX + ui.levelDrawAreaWidth)
      yOver = noteBoxY + noteBoxH - (dp.startY + ui.levelDrawAreaHeight)

    if xOver > 0:
      noteBoxX -= xOver
      textX -= xOver

    if yOver > 0:
      let offs = noteBoxH + 22
      noteBoxY -= offs
      textY -= offs

    vg.drawShadow(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                  ls.noteTooltipShadowStyle)

    vg.fillColor(a.theme.levelStyle.noteTooltipBackgroundColor)
    vg.beginPath()
    vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                   r=ls.noteTooltipCornerRadius)
    vg.fill()

    vg.fillColor(a.theme.levelStyle.noteTooltipTextColor)
    vg.textBox(textX, textY, breakWidth, note.text)

# }}}
# {{{ renderLevel()
proc renderLevel(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opts, a.opts)

  let l = currLevel(a)

  let i = instantiationInfo(fullPaths=true)
  let id = koi.generateId(i.filename, i.line, "gridmonger-level")

  updateViewStartAndCursorPosition(a)

  if ui.prevCursor != ui.cursor:
    resetManualNoteTooltip(a)

  let
    x = dp.startX
    y = dp.startY
    w = dp.viewCols * dp.gridSize
    h = dp.viewRows * dp.gridSize

  # Hit testing
  if koi.isHit(x, y, w, h):
    koi.setHot(id)
    if koi.hasNoActiveItem() and
       (koi.mbLeftDown() or koi.mbRightDown() or koi.mbMiddleDown()):
      koi.setActive(id)

  if koi.isHot(id) and isActive(id):
    handleLevelMouseEvents(a)

  # Draw level
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = ui.cursor.row
    dp.cursorCol = ui.cursor.col
    dp.cellCoordOpts = coordOptsForCurrLevel(a)
    dp.regionOpts = l.regionOpts

    dp.cursorOrient = CardinalDir.none
    if opts.walkMode and
       ui.editMode in {emNormal, emExcavateTunnel, emEraseCell,
                       emDrawClearFloor}:
      dp.cursorOrient = ui.cursorOrient.some

    dp.selection = ui.selection
    dp.selectionRect = ui.selRect

    dp.selectionBuffer =
      if   ui.editMode == emPastePreview: ui.copyBuf
      elif ui.editMode in {emMovePreview, emNudgePreview}: ui.nudgeBuf
      else: SelectionBuffer.none

    drawLevel(
      a.doc.map,
      ui.cursor.level,
      DrawLevelContext(ls: a.theme.levelStyle, dp: dp, vg: a.vg)
    )

  # Draw note tooltip
  const
    NoteTooltipXOffs = 16
    NoteTooltipYOffs = 20

  var mouseOverCellWithNote = false
  var note: Option[Annotation]

  if koi.isHot(id) and
     not (opts.wasdMode and isActive(id)) and
     (koi.mx() != ui.manualNoteTooltipState.mx or
      koi.my() != ui.manualNoteTooltipState.my):

    let loc = locationAtMouse(a)
    if loc.isSome:
      let loc = loc.get

      note = l.getNote(loc.row, loc.col)
      if note.isSome:
        mouseOverCellWithNote = true
        resetManualNoteTooltip(a)


  if ui.manualNoteTooltipState.show:
    let loc = ui.manualNoteTooltipState.location
    note = l.getNote(loc.row, loc.col)

  if note.isSome:
    var x, y: float

    if mouseOverCellWithNote:
      x = koi.mx() + NoteTooltipXOffs
      y = koi.my() + NoteTooltipYOffs

    elif ui.manualNoteTooltipState.show:
      x = dp.startX + viewCol(a) * dp.gridSize + NoteTooltipXOffs
      y = dp.startY + viewRow(a) * dp.gridSize + NoteTooltipYOffs

    renderNoteTooltip(x, y, note.get, a)


  a.ui.prevCursor = a.ui.cursor

# }}}
# {{{ renderEmptyMap()
proc renderEmptyMap(a) =
  alias(vg, a.vg)

  let ls = a.theme.levelStyle

  vg.setFont(22, "sans-bold")
  vg.fillColor(ls.foregroundNormalNormalColor)
  vg.textAlign(haCenter, vaMiddle)
  var y = drawAreaHeight(a) * 0.5
  discard vg.text(drawAreaWidth(a) * 0.5, y, "Empty map")

# }}}
# {{{ renderModeAndOptionIndicators()
proc renderModeAndOptionIndicators(a) =
  alias(vg, a.vg)
  alias(ui, a.ui)

  let ls = a.theme.levelStyle

  var x = ui.levelLeftPad
  let y = a.win.titleBarHeight + 32

  vg.save()

  vg.fillColor(ls.coordinatesHighlightColor)

  if a.opts.wasdMode:
    vg.setFont(15, "sans-bold")
    discard vg.text(x, y, fmt"WASD+{IconMouse}")
    x += 80

  if a.opts.drawTrail:
    vg.setFont(19, "sans-bold")
    discard vg.text(x, y+1, IconShoePrints)

# }}}

# {{{ renderToolsPane()

# {{{ specialWallDrawProc()
proc specialWallDrawProc(ls: LevelStyle,
                         ts: ToolbarPaneStyle,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               state: WidgetState, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var (bgCol, active) = case state
                          of wsActive:      (ls.cursorColor,       true)
                          of wsHover:       (ts.buttonHoverColor,  false)
                          of wsActiveHover: (ls.cursorColor,       true)
                          of wsDown:        (ls.cursorColor,       true)
                          else:             (ts.buttonNormalColor, false)

    # TODO store on theme change?
    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let
      savedFloorColor = ls.floorBackgroundColor[0]
      savedForegroundNormalNormalColor = ls.foregroundNormalNormalColor
      savedForegroundLightNormalColor = ls.foregroundLightNormalColor
      savedBackgroundImage = dp.backgroundImage

    ls.floorBackgroundColor[0] = lerp(ls.backgroundColor, bgCol, bgCol.a)
                                 .withAlpha(1.0)
    if active:
      ls.foregroundNormalNormalColor = ls.foregroundNormalCursorColor
      ls.foregroundLightNormalColor = ls.foregroundLightCursorColor

    dp.backgroundImage = Paint.none

    const Pad = 5

    vg.beginPath()
    vg.fillColor(bgCol)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill()

    dp.setZoomLevel(ls, 4)
    let ctx = DrawLevelContext(ls: ls, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel(zl: Natural, body: untyped) =
      vg.save()
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(ls, zl)
      vg.intersectScissor(x+4.5, y+3, w-Pad*2-4, h-Pad*2-2)
      body
      dp.setZoomLevel(ls, 4)
      vg.restore()

    let ot = Horiz

    case SpecialWalls[buttonIdx]
    of wNone:              discard
    of wWall:              drawSolidWallHoriz(cx, cy, ot, ctx=ctx)
    of wIllusoryWall:      drawIllusoryWallHoriz(cx+2, cy, ot, ctx=ctx)
    of wInvisibleWall:     drawInvisibleWallHoriz(cx-2, cy, ot, ctx=ctx)
    of wDoor:              drawDoorHoriz(cx, cy, ot, ctx=ctx)
    of wLockedDoor:        drawLockedDoorHoriz(cx, cy, ot, ctx=ctx)
    of wArchway:           drawArchwayHoriz(cx, cy, ot, ctx=ctx)

    of wSecretDoor:
      drawAtZoomLevel(6):  drawSecretDoorHoriz(cx-2, cy, ot, ctx=ctx)

    of wOneWayDoorNE:
      drawAtZoomLevel(8):  drawOneWayDoorHorizNE(cx-4, cy+1, ot, ctx=ctx)

    of wLeverSW:
      drawAtZoomLevel(6):  drawLeverHorizSW(cx-2, cy+1, ot, ctx=ctx)

    of wNicheSW:           drawNicheHorizSW(cx, cy, ot, floorColor=0, ctx=ctx)

    of wStatueSW:
      drawAtZoomLevel(6):  drawStatueHorizSW(cx-2, cy+2, ot, ctx=ctx)

    of wKeyhole:
      drawAtZoomLevel(6):  drawKeyholeHoriz(cx-2, cy, ot, ctx=ctx)

    of wWritingSW:
      drawAtZoomLevel(12): drawWritingHorizSW(cx-6, cy+4, ot, ctx=ctx)

    else: discard

    # ...aaaaand restore it!
    ls.floorBackgroundColor[0] = savedFloorColor
    ls.foregroundNormalNormalColor = savedForegroundNormalNormalColor
    ls.foregroundLightNormalColor = savedForegroundLightNormalColor
    dp.backgroundImage = savedBackgroundImage

# }}}

proc renderToolsPane(x, y, w, h: float; a) =
  alias(ui, a.ui)
  alias(ls, a.theme.levelStyle)

  var
    toolItemsPerColumn = 12
    toolX = x

    colorItemsPerColum = 10
    colorX = x + 3
    colorY = y + 445

  if drawAreaHeight(a) < ToolsPaneYBreakpoint2:
    colorItemsPerColum = 5
    toolX += 30

  if drawAreaHeight(a) < ToolsPaneYBreakpoint1:
    toolItemsPerColumn = 6
    toolX -= 30
    colorX += 3
    colorY -= 210

  # Draw special walls
  koi.radioButtons(
    x = toolX,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = SpecialWallTooltips,
    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: toolItemsPerColumn),

    drawProc = specialWallDrawProc(
      a.theme.levelStyle, a.theme.toolbarPaneStyle, ui.toolbarDrawParams
    ).some
  )

  # Draw floor colors
  var floorColors = newSeqOfCap[Color](ls.floorBackgroundColor.len)

  for fc in 0..ls.floorBackgroundColor.high:
    let c = calcBlendedFloorColor(fc, ls.floorTransparent, ls)
    floorColors.add(c)

  koi.radioButtons(
    x = colorX,
    y = colorY,
    w = 30,
    h = 30,
    labels = newSeq[string](ls.floorBackgroundColor.len),
    ui.currFloorColor,
    tooltips = @[],

    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: colorItemsPerColum),

    drawProc = colorRadioButtonDrawProc(floorColors,
                                        ls.cursorColor).some
  )

# }}}
# {{{ renderNotesPane()

# {{{ drawIndexedNote()
proc drawIndexedNote(x, y: float; size: float; bgColor, fgColor: Color;
                     shape: NoteBackgroundShape; index: Natural; a) =
  alias(vg, a.vg)

  vg.fillColor(bgColor)
  vg.beginPath()

  case shape
  of nbsCircle:
    vg.circle(x + size*0.5, y + size*0.5, size*0.38)
  of nbsRectangle:
    let pad = 4.0
    vg.rect(x+pad, y+pad, size-pad*2, size-pad*2)

  vg.fill()

  var fontSizeFactor = if   index <  10: 0.4
                       elif index < 100: 0.37
                       else:             0.32

  vg.setFont((size*fontSizeFactor).float, "sans-bold")
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + size*0.51, y + size*0.54, $index)

# }}}

proc renderNotesPane(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let s = a.theme.notesPaneStyle

  let
    l = currLevel(a)
    cur = a.ui.cursor
    note = l.getNote(cur.row, cur.col)

  if note.isSome and not (a.ui.editMode in {emPastePreview, emNudgePreview}):
    let note = note.get
    if note.text == "" or note.kind == akLabel: return

    vg.save()

    case note.kind
    of akIndexed:
      drawIndexedNote(x, y-12, size=36,
                      bgColor=s.indexBackgroundColor[note.indexColor],
                      fgColor=s.indexColor,
                      a.theme.levelStyle.notebackgroundShape,
                      note.index, a)

    of akCustomId:
      vg.fillColor(s.textColor)
      vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+18, y-2, note.customId)

    of akIcon:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-3, NoteIcons[note.icon])

    of akComment:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-2, IconComment)

    of akLabel: discard


    var text = note.text
    koi.textArea(x+40, y-11, w-20, h+10, text, disabled=true,
                 style=a.theme.noteTextAreaStyle)

    vg.restore()

# }}}

# {{{ renderCommand()
proc renderCommand(x, y: float; command: string; a): float =
  alias(vg, a.vg)

  let w = vg.textWidth(command)

  # TODO
  let s = a.theme.statusBarStyle

  let (x, y) = (round(x), round(y))

  vg.beginPath()
  vg.roundedRect(x, y-10, w+10, 18, 3)
  vg.fillColor(s.commandBackgroundColor)
  vg.fill()

  vg.fillColor(s.commandTextColor)
  discard vg.text(x+5, y, command)

  result = w

# }}}
# {{{ renderStatusBar()
proc renderStatusBar(y: float, winWidth: float; a) =
  alias(vg, a.vg)
  alias(status, a.ui.status)

  let s = a.theme.statusBarStyle

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.save()

  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(s.backgroundColor)
  vg.fill()

  # Display cursor coordinates
  vg.setFont(14, "sans-bold")

  if a.doc.map.hasLevels:
    let
      l = currLevel(a)
      coordOpts = coordOptsForCurrLevel(a)

      cur = a.ui.cursor
      row = formatRowCoord(cur.row, l.rows, coordOpts, l.regionOpts)
      col = formatColumnCoord(cur.col, l.cols, coordOpts, l.regionOpts)

      cursorPos = fmt"({col}, {row})"
      tw = vg.textWidth(cursorPos)

    vg.fillColor(s.coordinatesColor)
    vg.textAlign(haLeft, vaMiddle)
    discard vg.text(winWidth - tw - 7, ty, cursorPos)

    vg.intersectScissor(0, y, winWidth - tw - 15, StatusBarHeight)

  # Display status message or warning
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 14
    CommandTextPadX = 10

  var x = 10.0

  # Clear expired warning messages
  if status.warning != "":
    let dt = getMonoTime() - status.warningT0
    if dt > status.warningTimeout:
      status.warning = ""

      if not status.keepMessageAfterWarningExpired:
        clearStatusMessage(a)

  # Display message
  if status.warning == "":
    vg.fillColor(s.textColor)
    discard vg.text(IconPosX, ty, status.icon)

    let tx = vg.text(MessagePosX, ty, status.message)
    x = tx + MessagePadX

    # Display commands, if present
    for i, cmd in status.commands:
      if i mod 2 == 0:
        let w = renderCommand(x, ty, cmd, a)
        x += w + CommandLabelPadX
      else:
        let text = cmd
        vg.fillColor(s.textColor)
        let tw = vg.text(round(x), round(ty), text)
        x = tw + CommandTextPadX

  # Display warning
  else:
    # TODO
    vg.fillColor(a.theme.warningLabelStyle.color)

    discard vg.text(IconPosX, ty, IconWarning)
    discard vg.text(MessagePosX, ty, status.warning)

  vg.restore()

# }}}

# {{{ renderThemeEditorProps()

var ThemeEditorScrollViewStyle = getDefaultScrollViewStyle()
with ThemeEditorScrollViewStyle:
  vertScrollBarWidth      = 14.0
  scrollBarStyle.thumbPad = 4.0

var ThemeEditorSliderStyle = getDefaultSliderStyle()
with ThemeEditorSliderStyle:
  trackCornerRadius = 8.0
  valueCornerRadius = 6.0

var ThemeEditorAutoLayoutParams = DefaultAutoLayoutParams
with ThemeEditorAutoLayoutParams:
  leftPad    = 14.0
  rightPad   = 16.0
  labelWidth = 185.0

proc renderThemeEditorProps(x, y, w, h: float; a) =
  alias(te, a.themeEditor)
  alias(cfg, a.theme.config)

  template prop(label: string, path: string, body: untyped)  =
    block:
      koi.label(label)
      koi.setNextId(path)
      body
      if a.theme.prevConfig.getOpt(path) != cfg.getOpt(path):
        te.modified = true

  template stringProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getStringOrDefault(path)
      koi.textfield(val)
      cfg.set(path, $val)

  template colorProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getColorOrDefault(path)
      koi.color(val)
      cfg.set(path, $val)

  template boolProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getBoolOrDefault(path)
      koi.checkBox(val)
      cfg.set(path, val)

  template floatProp(label: string, path: string, limits: FieldLimits) =
    prop(label, path):
      var val = cfg.getFloatOrDefault(path)
      koi.horizSlider(startVal=limits.minFloat,
                      endVal=limits.maxFloat,
                      val,
                      style=ThemeEditorSliderStyle)
      cfg.set(path, val)

  template enumProp(label: string, path: string, T: typedesc[enum]) =
    prop(label, path):
      var val = cfg.getEnumOrDefault(path, T)
      koi.dropDown(val)
      cfg.set(path, enumToDashCase($val))


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  var p: string

  # {{{ User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      p = "ui.window."
      group:
        colorProp("Border",           p & "border.color")

      group:
        colorProp("Background",       p & "background.color")
        let path = p & "background.image"
        stringProp("Background Image", path)

        koi.nextLayoutColumn()
        if koi.button("Reload", disabled=cfg.getString(path) == ""):
          a.theme.loadBackgroundImage = true

      group:
        p = "ui.window.title."
        colorProp("Title Background Normal",   p & "background.normal")
        colorProp("Title Background Inactive", p & "background.inactive")
        colorProp("Title Text Normal",         p & "text.normal")
        colorProp("Title Text Inactive",       p & "text.inactive")

      group:
        p = "ui.window."
        colorProp("Modified Flag",    p & "modified-flag")

      group:
        p = "ui.window.button."
        colorProp("Button Normal",    p & "normal")
        colorProp("Button Hover",     p & "hover")
        colorProp("Button Down",      p & "down")
        colorProp("Button Inactive",  p & "inactive")

    if koi.subSectionHeader("Dialog", te.sectionDialog):
      p = "ui.dialog."
      group:
        let CRLimits = DialogCornerRadiusLimits
        floatProp("Corner Radius",    p & "corner-radius", CRLimits)
        colorProp("Background",       p & "background")
        colorProp("Label",            p & "label")
        colorProp("Warning",          p & "warning")
        colorProp("Error",            p & "error")

      group:
        colorProp("Title Background", p & "title.background")
        colorProp("Title Text",       p & "title.text")

      group:
        let BWLimits = DialogBorderWidthLimits
        colorProp("Outer Border",       p & "outer-border.color")
        floatProp("Outer Border Width", p & "outer-border.width", BWLimits)
        colorProp("Inner Border",       p & "inner-border.color")
        floatProp("Inner Border Width", p & "inner-border.width", BWLimits)

      group:
        boolProp( "Shadow?",         p & "shadow.enabled")
        colorProp("Shadow Colour",   p & "shadow.color")
        floatProp("Shadow Feather",  p & "shadow.feather",  ShadowFeatherLimits)
        floatProp("Shadow X Offset", p & "shadow.x-offset", ShadowOffsetLimits)
        floatProp("Shadow Y Offset", p & "shadow.y-offset", ShadowOffsetLimits)

    if koi.subSectionHeader("Widget", te.sectionWidget):
      p = "ui.widget."
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",       p & "corner-radius", WCRLimits)
      group:
        colorProp("Background Normal",   p & "background.normal")
        colorProp("Background Hover",    p & "background.hover")
        colorProp("Background Active",   p & "background.active")
        colorProp("Background Disabled", p & "background.disabled")
      group:
        colorProp("Foreground Normal",   p & "foreground.normal")
        colorProp("Foreground Active",   p & "foreground.active")
        colorProp("Foreground Disabled", p & "foreground.disabled")

    if koi.subSectionHeader("Text Field", te.sectionTextField):
      p = "ui.text-field."
      group:
        colorProp("Cursor",            p & "cursor")
        colorProp("Selection",         p & "selection")
      group:
        colorProp("Edit Background",   p & "edit.background")
        colorProp("Edit Text",         p & "edit.text")
      group:
        colorProp("Scroll Bar Normal", p & "scroll-bar.normal")
        colorProp("Scroll Bar Edit",   p & "scroll-bar.edit")

    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      p = "ui.status-bar."
      group:
        colorProp("Background",        p & "background")
        colorProp("Text",              p & "text")
        colorProp("Coordinates",       p & "coordinates")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      p = "ui.about-button."
      colorProp("Label Normal",        p & "label.normal")
      colorProp("Label Hover",         p & "label.hover")
      colorProp("Label Down",          p & "label.down")

    if koi.subSectionHeader("About Dialog", te.sectionAboutDialog):
      let path = "ui.about-dialog.logo"
      colorProp("Logo", path)
      if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
        a.aboutLogo.updateLogoImage = true

    if koi.subSectionHeader("Quick Help", te.sectionQuickHelp):
      p = "ui.quick-help."
      group:
        colorProp("Background",        p & "background")

    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        p = "ui.splash-image."
        var path = p & "logo"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateLogoImage = true

        path = p & "outline"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateOutlineImage = true

        path = p & "shadow-alpha"
        floatProp("Shadow Alpha", path, AlphaLimits)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      p = "level.general."
      group:
        colorProp("Background",            p & "background")
      group:
        enumProp( "Line Width",            p & "line-width", LineWidth)
      group:
        colorProp("Foreground Normal",        p & "foreground.normal.normal")
        colorProp("Foreground Normal Cursor", p & "foreground.normal.cursor")
        colorProp("Foreground Light",         p & "foreground.light.normal")
        colorProp("Foreground Light Cursor",  p & "foreground.light.cursor")
      group:
        colorProp("Link Marker",           p & "link-marker")
      group:
        colorProp("Trail Normal",          p & "trail.normal")
        colorProp("Trail Cursor",          p & "trail.cursor")
      group:
        colorProp("Cursor",                p & "cursor")
        colorProp("Cursor Guides",         p & "cursor-guides")
      group:
        colorProp("Selection",             p & "selection")
        colorProp("Paste Preview",         p & "paste-preview")
      group:
        colorProp("Coordinates Normal",    p & "coordinates.normal")
        colorProp("Coordinates Highlight", p & "coordinates.highlight")
      group:
        colorProp("Region Border Normal",  p & "region-border.normal")
        colorProp("Region Border Empty",   p & "region-border.empty")

    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      let WidthLimits = BackgroundHatchWidthLimits
      let SpacingLimits = BackgroundHatchSpacingFactorLimits

      p = "level.background-hatch."
      boolProp("Background Hatch?",     p & "enabled")
      colorProp("Hatch Colour",         p & "color")
      floatProp("Hatch Stroke Width",   p & "width",          WidthLimits)
      floatProp("Hatch Spacing Factor", p & "spacing-factor", SpacingLimits)

    if koi.subSectionHeader("Grid", te.sectionGrid):
      p = "level.grid."
      group:
        colorProp("Background Grid",       p & "background.grid")
        enumProp( "Background Grid Style", p & "background.style", GridStyle)
      group:
        colorProp("Floor Grid",            p & "floor.grid")
        enumProp( "Floor Grid Style",      p & "floor.style",      GridStyle)

    if koi.subSectionHeader("Outline", te.sectionOutline):
      p = "level.outline."
      enumProp( "Style",         p & "style",        OutlineStyle)
      enumProp( "Fill Style",    p & "fill-style",   OutlineFillStyle)
      colorProp("Outline",       p & "color")
      floatProp("Width",         p & "width-factor", OutlineWidthFactorLimits)
      boolProp( "Overscan",      p & "overscan")

    if koi.subSectionHeader("Shadow", te.sectionShadow):
      let SWLimits = ShadowWidthFactorLimits
      p = "level.shadow."
      group:
        colorProp("Inner Shadow",       p & "inner.color")
        floatProp("Inner Shadow Width", p & "inner.width-factor", SWLimits)
      group:
        colorProp("Outer Shadow",       p & "outer.color")
        floatProp("Outer Shadow Width", p & "outer.width-factor", SWLimits)

    if koi.subSectionHeader("Floor Colours", te.sectionFloorColors):
      p = "level.floor."
      boolProp("Transparent?", p & "transparent")

      colorProp("Color 1",  p & "background.0")
      colorProp("Color 2",  p & "background.1")
      colorProp("Color 3",  p & "background.2")
      colorProp("Color 4",  p & "background.3")
      colorProp("Color 5",  p & "background.4")
      colorProp("Color 6",  p & "background.5")
      colorProp("Color 7",  p & "background.6")
      colorProp("Color 8",  p & "background.7")
      colorProp("Color 9",  p & "background.8")
      colorProp("Color 10", p & "background.9")

    if koi.subSectionHeader("Notes", te.sectionNotes):
      p = "level.note."
      group:
        colorProp("Marker Normal",      p & "marker.normal")
        colorProp("Marker Cursor",      p & "marker.cursor")
        colorProp("Comment",            p & "comment")
      group:
        enumProp( "Background Shape",   p & "background-shape",
                  NoteBackgroundShape)

        colorProp("Background 1",       p & "index-background.0")
        colorProp("Background 2",       p & "index-background.1")
        colorProp("Background 3",       p & "index-background.2")
        colorProp("Background 4",       p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Tooltip Background",     p & "tooltip.background")
        colorProp("Tooltip Text",           p & "tooltip.text")
        floatProp("Tooltip Corner Radius ", p & "tooltip.corner-radius",
                  WidgetCornerRadiusLimits)
        colorProp("Tooltip Shadow",         p & "tooltip.shadow.color")

    if koi.subSectionHeader("Labels", te.sectionLabels):
      p = "level.label."
      group:
        colorProp("Label 1", p & "text.0")
        colorProp("Label 2", p & "text.1")
        colorProp("Label 3", p & "text.2")
        colorProp("Label 4", p & "text.3")

    if koi.subSectionHeader("Level Drop Down", te.sectionLevelDropDown):
      p = "level.level-drop-down."
      group:
        colorprop("Button Normal",        p & "button.normal")
        colorprop("Button Hover",         p & "button.hover")
        colorprop("Button Label",         p & "button.label")
      group:
        colorprop("Item List Background", p & "item-list-background")
        colorprop("Item Normal",          p & "item.normal")
        colorprop("Item Hover",           p & "item.hover")
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",        p & "corner-radius", WCRLimits)
      group:
        colorProp("Shadow",               p & "shadow.color")

  # }}}
  # {{{ Panes section

  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Notes Pane", te.sectionNotesPane):
      p = "pane.notes."
      group:
        colorProp("Text",               p & "text")
      group:
        colorProp("Index Background 1", p & "index-background.0")
        colorProp("Index Background 2", p & "index-background.1")
        colorProp("Index Background 3", p & "index-background.2")
        colorProp("Index Background 4", p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Scroll Bar",         p & "scroll-bar")

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      p = "pane.toolbar."
      colorProp("Button",       p & "button.normal")
      colorProp("Button Hover", p & "button.hover")

  # }}}

  koi.endScrollView()

  a.theme.prevConfig = cfg.deepCopy()

# }}}
# {{{ renderThemeEditorPane()

var g_themeEditorPropsFocusCaptured: bool

proc renderThemeEditorPane(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let topSectionHeight = 130
  let propsHeight = h - topSectionHeight

  # Background
  vg.beginPath()
  vg.rect(x, y, w, h)
  vg.fillColor(gray(0.3))
  vg.fill()

  # Left separator line
  vg.strokeWidth(1.0)
  vg.lineCap(lcjSquare)

  vg.beginPath()
  vg.moveTo(x+0.5, y)
  vg.lineTo(x+0.5, y+h)
  vg.strokeColor(gray(0.1))
  vg.stroke()

  let
    bw = 66.0
    bp = 7.0
    wh = 22.0

  var cx = x
  var cy = y

  # Theme pane title
  const TitleHeight = 34

  vg.beginPath()
  vg.rect(x+1, y, w, h=TitleHeight)
  vg.fillColor(gray(0.25))
  vg.fill()

  let titleStyle = getDefaultLabelStyle()
  titleStyle.align = haCenter

  cy += 6.0
  koi.label(cx, cy, w, wh, "T  H  E  M  E       E  D  I  T  O  R",
            style=titleStyle)

  # Theme name & action buttons

  vg.beginPath()
  vg.rect(x+1, y+TitleHeight, w, h=96)
  vg.fillColor(gray(0.36))
  vg.fill()

  cx = x+15
  cy += 45.0
  koi.label(cx, cy, w, wh, "Theme")

  let buttonsDisabled = koi.isDialogOpen()

  var themeNames = newSeq[string]()
  for t in a.theme.themeNames:
    themeNames.add(t.name)

  var themeIndex = a.theme.currThemeIndex

  cx += 60.0
  koi.dropDown(
    cx, cy, w=196.0, wh,
    themeNames,
    themeIndex,
    tooltip = "",
    disabled = buttonsDisabled
  )

  if themeIndex != a.theme.currThemeIndex:
    a.theme.nextThemeIndex = themeIndex.some

  # User theme indicator
  cx += 201

  var labelStyle = getDefaultLabelStyle()
  if not a.currThemeName.userTheme:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "U", style=labelStyle)

  # User theme override indicator
  cx += 13

  labelStyle = getDefaultLabelStyle()
  if not a.currThemeName.override:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "O", style=labelStyle)

  # Theme action buttons
  cx = x+15
  cy += 40.0

  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    saveTheme(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Copy", disabled=buttonsDisabled):
    openCopyThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Rename",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openRenameThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openDeleteThemeDialog(a)

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(g_themeEditorPropsFocusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  g_themeEditorPropsFocusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  a.theme.updateThemeStyles = true

# }}}

# {{{ Quick reference definition
type
  QuickRefItemKind = enum
    qkShortcut, qkKeyShortcuts, qkCustomShortcuts, qkDescription, qkSeparator

  QuickRefItem = object
    sepa: char
    case kind: QuickRefItemKind
    of qkShortcut:        shortcut:        AppShortcut
    of qkKeyShortcuts:    keyShortcuts:    seq[KeyShortcut]
    of qkCustomShortcuts: customShortcuts: seq[string]
    of qkDescription:     description:     string
    of qkSeparator:      discard

proc sc(sc: AppShortcut): QuickRefItem =
  QuickRefItem(kind: qkShortcut, shortcut: sc)

proc sc(sc: seq[AppShortcut], sepa = '/'): QuickRefItem =
  var shortcuts: seq[KeyShortcut] = @[]
  for s in sc: shortcuts.add(g_appShortcuts[s][0])
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: shortcuts, sepa: sepa)

proc sc(sc: KeyShortcut): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: @[sc])

proc sc(sc: seq[KeyShortcut], sepa = '/'): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: sc, sepa: sepa)

proc csc(s: seq[string]): QuickRefItem =
  QuickRefItem(kind: qkCustomShortcuts, customShortcuts: s)

proc desc(s: string): QuickRefItem =
  QuickRefItem(kind: qkDescription, description: s)

const QuickRefSepa = QuickRefItem(kind: qkSeparator)

# {{{ General
let g_quickRef_General = @[
  @[
    scNewMap.sc,            "New map".desc,
    scOpenMap.sc,           "Open map".desc,
    scSaveMap.sc,           "Save map".desc,
    scSaveMapAs.sc,         "Save map as".desc,
    scEditMapProps.sc,      "Edit map properties".desc,
    QuickRefSepa,

    scNewLevel.sc,          "New level".desc,
    scDeleteLevel.sc,       "Delete level".desc,
    scEditLevelProps.sc,    "Edit level properties".desc,
    QuickRefSepa,

    scEditRegionProps.sc,   "Edit region properties".desc,
    QuickRefSepa,

    scPreviousLevel.sc,     "Previous level".desc,
    scNextLevel.sc,         "Next level".desc,

    scToggleCellCoords.sc,  "Toggle cell coordinates".desc,
    scToggleNotesPane.sc,   "Toggle notes pane".desc,
    scToggleToolsPane.sc,   "Toggle tools pane".desc,
  ],
  @[
    @[scZoomIn,
      scZoomOut].sc,        "Zoom in/out".desc,
    QuickRefSepa,

    scUndo.sc,              "Undo last action".desc,
    scRedo.sc,              "Redo last action".desc,

    scToggleWalkMode.sc,    "Toggle walk mode".desc,
    scToggleWasdMode.sc,    "Toggle WASD mode".desc,
    QuickRefSepa,

    scShowNoteTooltip.sc,   "Display note tooltip".desc,
    QuickRefSepa,

    scPreviousTheme.sc,     "Previous theme".desc,
    scNextTheme.sc,         "Next theme".desc,
    scReloadTheme.sc,       "Reload current theme".desc,
    QuickRefSepa,

    scShowAboutDialog.sc,      "Show about dialog".desc,
    scToggleQuickReference.sc, "Show quick keyboard reference".desc,
    scOpenUserManual.sc,       "Open user manual in browser".desc,
    QuickRefSepa,

    scEditPreferences.sc,   "Preferences".desc,
    QuickRefSepa,

    scToggleThemeEditor.sc, "Toggle theme editor".desc,
    scToggleTitleBar.sc,    "Toggle title bar".desc,
  ]
]
# }}}
# {{{ Editing
let g_quickRef_Editing = @[
  @[
    scExcavateTunnel.sc,         "Excavate".desc,
    scEraseCell.sc,              "Erase cell".desc,
    scDrawClearFloor.sc,         "Clear floor".desc,
    scToggleFloorOrientation.sc, "Toggle floor orientation".desc,
    QuickRefSepa,

    @[scCycleFloorGroup1Forward,
      scCycleFloorGroup1Backward].sc, "Cycle door".desc,

    @[scCycleFloorGroup2Forward,
      scCycleFloorGroup2Backward].sc, "Cycle special door".desc,

    @[scCycleFloorGroup3Forward,
      scCycleFloorGroup3Backward].sc, "Cycle pressure plate".desc,

    @[scCycleFloorGroup4Forward,
      scCycleFloorGroup4Backward].sc, "Cycle pit".desc,

    @[scCycleFloorGroup5Forward,
      scCycleFloorGroup5Backward].sc, "Cycle special".desc,

    @[scCycleFloorGroup6Forward,
      scCycleFloorGroup6Backward].sc, "Cycle entry/exit".desc,

    @[scCycleFloorGroup7Forward,
      scCycleFloorGroup7Backward].sc, "Draw bridge".desc,
    QuickRefSepa,

    scSelectSpecialWall1.sc,  "Special wall: Open door".desc,
    scSelectSpecialWall2.sc,  "Special wall: Locked door".desc,
    scSelectSpecialWall3.sc,  "Special wall: Archway".desc,
    scSelectSpecialWall4.sc,  "Special wall: Secret Door".desc,
    scSelectSpecialWall5.sc,  "Special wall: One-way door".desc,
    scSelectSpecialWall6.sc,  "Special wall: Illusory wall".desc,
    scSelectSpecialWall7.sc,  "Special wall: Invisible wall".desc,
    scSelectSpecialWall8.sc,  "Special wall: Lever".desc,
    scSelectSpecialWall9.sc,  "Special wall: Niche".desc,
    scSelectSpecialWall10.sc, "Special wall: Statue".desc,
    scSelectSpecialWall11.sc, "Special wall: Keyhole".desc,
    scSelectSpecialWall12.sc, "Special wall: Writing".desc,
  ],
  @[
    scDrawWall.sc,            "Toggle wall".desc,
    scDrawSpecialWall.sc,     "Toggle special wall".desc,

    @[scPreviousSpecialWall,
      scNextSpecialWall].sc,  "Prev/next special wall".desc,
    QuickRefSepa,

    @[scPreviousFloorColor,
      scNextFloorColor].sc,   "Prev/next floor colour".desc,

    scSetFloorColor.sc,       "Set floor colour".desc,
    scPickFloorColor.sc,      "Pick floor colour".desc,
    QuickRefSepa,

    scToggleDrawTrail.sc,     "Toggle draw trail".desc,
    scExcavateTrail.sc,       "Excavate trail in current level".desc,
    scClearTrail.sc,          "Clear trail in current level".desc,
    scEraseTrail.sc,          "Erase trail".desc,
    QuickRefSepa,

    scMarkSelection.sc,       "Enter Select (Mark) mode".desc,
    scPaste.sc,               "Paste copy buffer contents".desc,
    scPastePreview.sc,        "Enter Paste Preview mode".desc,
    QuickRefSepa,

    scEditNote.sc,            "Create/edit note".desc,
    scEraseNote.sc,           "Erase note".desc,
    scEditLabel.sc,           "Create/edit text label".desc,
    scEraseLabel.sc,          "Erase text label".desc,
    QuickRefSepa,

    scJumpToLinkedCell.sc,    "Jump to other side of link".desc,
    scLinkCell.sc,            "Set link destination".desc,
    QuickRefSepa,

    scResizeLevel.sc,         "Resize level".desc,
    scNudgePreview.sc,        "Enter Nudge Level mode".desc,
    QuickRefSepa,
  ]
]
# }}}
# {{{ Dialogs
let g_quickRef_Dialogs = @[
  @[
    KeyShortcut(key: keyTab,
                mods: {mkShift}).sc, "Previous text input field".desc,

    scNextTextField.sc, "Next text input field".desc,
    QuickRefSepa,

    @[KeyShortcut(key: key1, mods: {mkCtrl}),
      KeyShortcut(key: key9, mods: {mkCtrl})].sc(sepa='-'), "Go to tab 1-9".desc,

    @[fmt"Ctrl-{IconArrowsHoriz}"].csc, "Switch current tab".desc,
    QuickRefSepa,

    @[fmt"{IconArrowsAll}"].csc, "Change radio button selection".desc,
    QuickRefSepa,

    scAccept.sc,  "Confirm".desc,
    scCancel.sc,  "Cancel".desc,
    scDiscard.sc, "Discard".desc,
  ]
]
# }}}

let g_quickRefShortcuts = @[
  g_quickRef_General,
  g_quickRef_Editing,
  g_quickRef_Dialogs
]

# }}}
# {{{ renderQuickReference()

proc renderQuickReference(a) =
  alias(vg, a.vg)
  let cfg = a.theme.config

  const
    h = 24.0
    sepaH = 14.0
    defaultColWidth = 105.0

  let textColor = a.theme.statusBarStyle.textColor

  proc renderSection(x, y: float; items: seq[QuickRefItem];
                     colWidth: float; a) =
    var
      x0 = x
      x = x
      y = y
      heightInc = h

    vg.setFont(14, "sans-bold")

    for item in items:
      case item.kind
      of qkShortcut:
        let shortcuts = g_appShortcuts[item.shortcut]
        heightInc = 0.0
        var ys = y
        for sc in shortcuts:
          let shortcut = sc.toStr()
          discard renderCommand(x, ys, shortcut, a)
          ys += h
          heightInc += h
        if shortcuts.len > 1: heightInc += sepaH
        x += colWidth

      of qkKeyShortcuts:
        var sx = x
        for idx, sc in item.keyShortcuts:
          let shortcut = sc.toStr()
          var xa = renderCommand(sx, y, shortcut, a)
          if idx < item.keyShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = h

      of qkCustomShortcuts:
        var sx = x
        for idx, shortcut in item.customShortcuts:
          var xa = renderCommand(sx, y, shortcut, a)
          if idx < item.customShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = h


      of qkDescription:
        vg.fillColor(textColor)
        discard vg.text(round(x), round(y), item.description)
        x = x0
        y += heightInc

      of qkSeparator:
        y += sepaH

  let
    uiWidth = drawAreaWidth(a)
    uiHeight = drawAreaHeight(a)
    yOffs = max((uiHeight - 750) * 0.5, 0)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.save()
    vg.intersectScissor(0, 0, uiWidth, uiHeight)

  koi.addDrawLayer(koi.currentLayer(), vg):
    # Background
    vg.beginPath()
    vg.rect(0, 0, uiWidth, uiHeight)
    vg.fillColor(cfg.getColorOrDefault("ui.quick-help.background"))
    vg.fill()

    # Title
    vg.setFont(20, "sans-bold")
    vg.fillColor(textColor.withAlpha(0.6))
    vg.textAlign(haCenter, vaMiddle)
    discard vg.text(round(uiWidth*0.5), 60+yOffs, "Quick Keyboard Reference")

  let
    t = invLerp(WindowMinWidth.float, 800.0, uiWidth).clamp(0.0, 1.0)
    viewWidth = lerp(622.0, 680.0, t)
    columnWidth = lerp(300.0, 330.0, t)
    tabWidth = 420.0

  let radioButtonX = (uiWidth - tabWidth)*0.5

  koi.radioButtons(
    radioButtonX, 92+yOffs, tabWidth, 24,
    g_quickRefTabLabels, a.quickRef.activeTab,
    style = a.theme.radioButtonStyle
  )

  koi.beginScrollView(x = (uiWidth - viewWidth)*0.5 + 4, y = 150+yOffs,
                      w = viewWidth, h = (uiHeight - 162))

  var a = a
  var (sx, sy) = addDrawOffset(10, 10)

  let (viewHeight, colWidth) = case a.quickRef.activeTab
  of 0: (525.0, defaultColWidth)
  of 1: (592.0, defaultColWidth)
  else: (400.0, defaultColWidth + 30)

  koi.addDrawLayer(koi.currentLayer(), vg):
    let items = g_quickRefShortcuts[a.quickRef.activeTab]
    if items.len == 1: sx = radioButtonX + 70
    for r in items:
      renderSection(sx, sy, r, colWidth, a)
      sx += columnWidth

  koi.endScrollView(viewHeight)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.restore()

# }}}

# {{{ renderLevelDropdown()
proc renderLevelDropdown(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    levelNames = map.sortedLevelNames
    uiWidth = drawAreaWidth(a)
    yStart = a.win.titleBarHeight

  var sortedLevelIdx = currSortedLevelIdx(a)
  let prevSortedLevelIdx = sortedLevelIdx

  vg.fontSize(a.theme.levelDropDownStyle.label.fontSize)

  # Level drop-down
  let levelDropDownWidth = round(
    vg.textWidth(levelNames[sortedLevelIdx]) +
    a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
  )

  koi.dropDown(
    x = round((uiWidth - levelDropDownWidth) * 0.5),
    y = yStart + 19.0,
    w = levelDropDownWidth,
    h = 24.0,
    levelNames,
    sortedLevelIdx,
    tooltip = "",
    disabled = not (ui.editMode in {emNormal, emSetCellLink}),
    style = a.theme.levelDropDownStyle
  )

  if sortedLevelIdx != prevSortedLevelIdx:
    var cur = ui.cursor
    cur.level = map.sortedLevelIdxToLevelIdx[sortedLevelIdx]
    setCursor(cur, a)
# }}}
# {{{ renderRegionDropDown()
proc renderRegionDropDown(a) =
  alias(ui, a.ui)

  let
    l = currLevel(a)
    currRegion = currRegion(a)
    uiWidth = drawAreaWidth(a)

  if currRegion.isSome:
    var sortedRegionNames = l.regionNames()
    sort(sortedRegionNames)

    let currRegionName = currRegion.get.name
    var sortedRegionIdx = sortedRegionNames.find(currRegionName)
    let prevSortedRegionIdx = sortedRegionIdx

    let regionDropDownWidth = round(
      a.vg.textWidth(currRegionName) +
      a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
    )

    koi.dropDown(
      x = round((uiWidth - regionDropDownWidth) * 0.5),
      y = 73.0,
      w = regionDropDownWidth,
      h = 24.0,
      sortedRegionNames,
      sortedRegionIdx,
      tooltip = "",
      disabled = not (ui.editMode in {emNormal, emSetCellLink}),
      style = a.theme.levelDropDownStyle
    )

    if sortedRegionIdx != prevSortedRegionIdx :
      let currRegionName = sortedRegionNames[sortedRegionIdx]
      let (regionCoords, _) = l.findFirstRegionByName(currRegionName).get

      let (r, c) = a.doc.map.getRegionCenterLocation(ui.cursor.level,
                                               regionCoords)

      centerCursorAt(Location(level: ui.cursor.level, row: r, col: c), a)
# }}}
# {{{ renderDialogs()
proc renderDialogs(a) =
  alias(dlg, a.dialogs)

  case dlg.activeDialog:
  of dlgNone: discard

  of dlgAboutDialog:
    aboutDialog(a)

  of dlgPreferencesDialog:
    preferencesDialog(dlg.preferencesDialog, a)

  of dlgSaveDiscardMapDialog:
    saveDiscardMapDialog(dlg.saveDiscardMapDialog, a)

  of dlgNewMapDialog:
    newMapDialog(dlg.newMapDialog, a)

  of dlgEditMapPropsDialog:
    editMapPropsDialog(dlg.editMapPropsDialog, a)

  of dlgNewLevelDialog:
    newLevelDialog(dlg.newLevelDialog, a)

  of dlgDeleteLevelDialog:
    deleteLevelDialog(a)

  of dlgEditLevelPropsDialog:
    editLevelPropsDialog(dlg.editLevelPropsDialog, a)

  of dlgEditNoteDialog:
    editNoteDialog(dlg.editNoteDialog, a)

  of dlgEditLabelDialog:
    editLabelDialog(dlg.editLabelDialog, a)

  of dlgResizeLevelDialog:
    resizeLevelDialog(dlg.resizeLevelDialog, a)

  of dlgEditRegionPropsDialog:
    editRegionPropsDialog(dlg.editRegionPropsDialog, a)

  of dlgSaveDiscardThemeDialog:
    saveDiscardThemeDialog(dlg.saveDiscardThemeDialog, a)

  of dlgCopyThemeDialog:
    copyThemeDialog(dlg.copyThemeDialog, a)

  of dlgRenameThemeDialog:
    renameThemeDialog(dlg.renameThemeDialog, a)

  of dlgOverwriteThemeDialog:
    overwriteThemeDialog(dlg.overwriteThemeDialog, a)

  of dlgDeleteThemeDialog:
    deleteThemeDialog(a)

# }}}
# {{{ renderUI()
proc renderUI(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let winHeight = koi.winHeight()
  let uiWidth = drawAreaWidth(a)
  let yStart = a.win.titleBarHeight

  # Clear background
  vg.beginPath()
  vg.rect(0, a.win.titleBarHeight, uiWidth, drawAreaHeight(a))

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.windowStyle.backgroundColor)

  vg.fill()

  if a.opts.showQuickReference:
    renderQuickReference(a)

  else:
    # About button
    if button(x=uiWidth-55.0, y=yStart+19.0, w=20.0, h=DlgItemHeight,
              IconQuestion, style=a.theme.aboutButtonStyle, tooltip="About"):
      openAboutDialog(a)

    if not map.hasLevels:
      renderEmptyMap(a)

    else:
      renderLevelDropdown(a)

      if currLevel(a).regionOpts.enabled:
        renderRegionDropDown(a)

      renderLevel(a)

      if a.opts.showNotesPane:
        renderNotesPane(
          x = NotesPaneLeftPad,
          y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
          w = uiWidth - toolsPaneWidth(a) - NotesPaneLeftPad - NotesPaneRightPad,
          h = NotesPaneHeight,
          a
        )

      if a.opts.showToolsPane:
        renderToolsPane(
          x = uiWidth - toolsPaneWidth(a),
          y = yStart + ToolsPaneTopPad,
          w = toolsPaneWidth(a),
          h = winHeight - StatusBarHeight - ToolsPaneBottomPad,
          a
        )

      renderModeAndOptionIndicators(a)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, uiWidth.float, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.opts.showThemeEditor:
    let
      x = uiWidth
      y = yStart
      w = ThemePaneWidth
      h = drawAreaHeight(a)

    renderThemeEditorPane(x, y, w, h, a)

  renderDialogs(a)

# }}}

# {{{ renderFramePre()
proc renderFramePre(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      a.theme.themeReloaded = (themeIndex == a.theme.currThemeIndex)
      switchTheme(themeIndex, a)

    except CatchableError as e:
      logError(e, "Error loading theme when switching theme")
      let name = a.theme.themeNames[themeIndex].name

      setWarningMessage(fmt"Cannot load theme '{name}': {e.msg}",
                        autohide=false, a=a)

      a.theme.nextThemeIndex = Natural.none

    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message


  if a.theme.nextThemeIndex.isSome:
    loadPendingTheme(a.theme.nextThemeIndex.get, a)

  a.win.title = a.doc.map.title
  a.win.modified = a.doc.undoManager.isModified

  if a.theme.updateThemeStyles:
    a.theme.updateThemeStyles = false
    updateThemeStyles(a)

  if a.theme.loadBackgroundImage:
    a.theme.loadBackgroundImage = false
    loadBackgroundImage(a.currThemeName, a)

  a.updateUI = true

# }}}
# {{{ renderFrame()

proc closeSplash(a)

proc renderFrame(a) =

  proc displayThemeLoadedMessage(a) =
    let themeName = a.currThemeName.name
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
      a.theme.themeReloaded = false
    else:
      setStatusMessage(fmt"Theme '{themeName}' loaded", a)

  if a.theme.nextThemeIndex.isSome:
    if a.theme.hideThemeLoadedMessage:
      a.theme.hideThemeLoadedMessage = false
    else:
      displayThemeLoadedMessage(a)
    a.theme.nextThemeIndex = Natural.none

  proc handleWindowClose(a) =
    proc saveConfigAndExit(a) =
      saveAppConfig(a)
      a.shouldClose = true

    proc handleMapModified(a) =
      if not koi.isDialogOpen():
        if a.doc.undoManager.isModified:
          openSaveDiscardMapDialog(action=saveConfigAndExit, a)
        else:
          saveConfigAndExit(a)

    when defined(NO_QUIT_DIALOG):
      saveConfigAndExit(a)
    else:
      if a.themeEditor.modified:
        openSaveDiscardThemeDialog(action=handleMapModified, a)
      else:
        handleMapModified(a)

  # XXX HACK: If the theme pane is shown, widgets are handled first, then
  # the global shortcuts, so widget-specific shorcuts can take precedence
  var uiRendered = false
  if a.opts.showThemeEditor:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if a.opts.showQuickReference: handleQuickRefKeyEvents(a)
    elif a.doc.map.hasLevels:     handleGlobalKeyEvents(a)
    else:                         handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.opts.showThemeEditor and a.win.glfwWin.focused:
      glfw.makeContextCurrent(a.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(a.win.glfwWin)
      a.win.focus()

  if not a.opts.showThemeEditor or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash(a) =
  alias(s, a.splash)
  alias(vg, s.vg)

  let cfg = a.theme.config

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth / winWidth

  glViewport(0, 0, fbWidth, fbHeight)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)

  if s.logoImage == NoImage or s.updateLogoImage:
    colorImage(s.logo, cfg.getColorOrDefault("ui.splash-image.logo"))
    if s.logoImage == NoImage:
      s.logoImage = createImage(s.logo)
    else:
      vg.updateImage(s.logoImage, cast[ptr byte](s.logo.data))
    s.updateLogoImage = false

  if s.outlineImage == NoImage or s.updateOutlineImage:
    colorImage(s.outline, cfg.getColorOrDefault("ui.splash-image.outline"))
    if s.outlineImage == NoImage:
      s.outlineImage = createImage(s.outline)
    else:
      vg.updateImage(s.outlineImage, cast[ptr byte](s.outline.data))
    s.updateOutlineImage = false

  if s.shadowImage == NoImage or s.updateShadowImage:
    colorImage(s.shadow, black())
    if s.shadowImage == NoImage:
      s.shadowImage = createImage(s.shadow)
    else:
      vg.updateImage(s.shadowImage, cast[ptr byte](s.shadow.data))
    s.updateShadowImage = false


  let scale = winWidth / s.logo.width

  s.logoPaint = createPattern(vg, s.logoImage, scale=scale)

  s.outlinePaint = createPattern(vg, s.outlineImage, scale=scale)

  s.shadowPaint = createPattern(
    vg, s.shadowImage,
    alpha=cfg.getFloatOrDefault("ui.splash-image.shadow-alpha"),
    scale=scale
  )

  vg.beginPath()
  vg.rect(0, 0, winWidth.float, winHeight.float)

  vg.fillPaint(s.shadowPaint)
  vg.fill()

  vg.fillPaint(s.outlinePaint)
  vg.fill()

  vg.fillPaint(s.logoPaint)
  vg.fill()

  vg.endFrame()


  if not a.opts.showThemeEditor and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.opts.showThemeEditor:
      not a.splash.show
    else:
      let autoClose =
        if not a.opts.showThemeEditor and a.prefs.autoCloseSplash:
          let dt = getMonoTime() - a.splash.t0
          koi.setFramesLeft()
          dt > initDuration(seconds = a.prefs.splashTimeoutSecs)
        else: false

      w.isKeyDown(keyEscape) or
      w.isKeyDown(keySpace) or
      w.isKeyDown(keyEnter) or
      w.isKeyDown(keyKpEnter) or
      w.mouseButtonDown(mbLeft) or
      w.mouseButtonDown(mbRight) or
      w.mouseButtonDown(mbMiddle) or autoClose

  if shouldCloseSplash(a):
    closeSplash(a)
    a.win.focus()

# }}}

# }}}

# {{{ Init & cleanup

# {{{ createSplashWindow()
proc createSplashWindow(mousePassthru: bool = false; a) =
  alias(s, a.splash)

  var cfg = DefaultOpenglWindowConfig
  cfg.visible = false
  cfg.resizable = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.nMultiSamples = 4
  cfg.transparentFramebuffer = true
  cfg.decorated = false
  cfg.floating = true

  when defined(windows):
    cfg.hideFromTaskbar = true
    cfg.mousePassthru = mousePassthru
  else:
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  s.win = newWindow(cfg)
  s.vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

# }}}
# {{{ showSplash()
proc showSplash(a) =
  alias(s, g_app.splash)

  let (_, _, maxWidth, maxHeight) = getPrimaryMonitor().workArea
  let w = (maxWidth * 0.6).int32
  let h = (w/s.logo.width * s.logo.height).int32

  s.win.size = (w, h)
  s.win.pos = ((maxWidth - w) div 2, (maxHeight - h) div 2)
  s.win.show()

  if not a.opts.showThemeEditor:
    koi.setFocusCaptured(true)

# }}}
# {{{ closeSplash()
proc closeSplash(a) =
  alias(s, a.splash)

  s.win.destroy()
  s.win = nil

  s.vg.deleteImage(s.logoImage)
  s.vg.deleteImage(s.outlineImage)
  s.vg.deleteImage(s.shadowImage)

  s.logoImage = NoImage
  s.outlineImage = NoImage
  s.shadowImage = NoImage

  nvgDeleteContext(s.vg)
  s.vg = nil

  s.show = false

  if not a.opts.showThemeEditor:
    koi.setFocusCaptured(false)

# }}}

# {{{ loadAndSetIcon()
proc loadAndSetIcon(a) =
  alias(p, a.paths)

  var icons: array[5, wrapper.IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width = img.width.int32
    icons[idx].height = img.height.int32
    icons[idx].pixels = cast[ptr uint8](img.data)

  var icon32  = loadImage(p.dataDir / "icon32.png")
  var icon48  = loadImage(p.dataDir / "icon48.png")
  var icon64  = loadImage(p.dataDir / "icon64.png")
  var icon128 = loadImage(p.dataDir / "icon128.png")
  var icon256 = loadImage(p.dataDir / "icon256.png")

  add(0, icon32)
  add(1, icon48)
  add(2, icon64)
  add(3, icon128)
  add(4, icon256)

  a.win.glfwWin.icons = icons

# }}}
# {{{ loadFonts()
proc loadFonts(a) =
  alias(p, a.paths)

  proc loadFont(fontName: string, filename: string; a): Font =
    try:
      a.vg.createFont(fontName, filename)
    except CatchableError as e:
      logging.error(fmt"Cannot load font '{filename}'")
      raise e

  discard         loadFont("sans",       p.dataDir / "Roboto-Regular.ttf", a)
  let boldFont  = loadFont("sans-bold",  p.dataDir / "Roboto-Bold.ttf", a)
  let blackFont = loadFont("sans-black", p.dataDir / "Roboto-Black.ttf", a)
  let iconFont  = loadFont("icon",       p.dataDir / "GridmongerIcons.ttf", a)

  discard addFallbackFont(a.vg, boldFont, iconFont)
  discard addFallbackFont(a.vg, blackFont, iconFont)

# }}}
# {{{ loadSplashmages()
proc loadSplashImages(a) =
  alias(s, a.splash)
  alias(p, a.paths)

  s.logo    = loadImage(p.dataDir / "logo.png")
  s.outline = loadImage(p.dataDir / "logo-outline.png")
  s.shadow  = loadImage(p.dataDir / "logo-shadow.png")

  createAlpha(s.logo)
  createAlpha(s.outline)
  createAlpha(s.shadow)

# }}}
# {{{ loadAboutLogoImage()
proc loadAboutLogoImage(a) =
  alias(al, a.aboutLogo)

  al.logo = loadImage(a.paths.dataDir / "logo-small.png")
  createAlpha(al.logo)

# }}}

# {{{ setDefaultWidgetStyles()
proc setDefaultWidgetStyles(a) =
  var s = koi.getDefaultCheckBoxStyle()

  s.icon.fontSize = 12.0
  s.iconActive    = IconCheck
  s.iconInactive  = NoIcon

  koi.setDefaultCheckboxStyle(s)

# }}}
#
# {{{ initGfx()
proc initGfx(a) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    logging.error("Error initialising OpenGL")
    quit(QuitFailure)

  let version  = cast[cstring](glGetString(GL_VERSION))
  let vendor   = cast[cstring](glGetString(GL_VENDOR))
  let renderer = cast[cstring](glGetString(GL_RENDERER))

  let msg = fmt"""
GPU info
  Vendor:   {vendor}
  Renderer: {renderer}
  Version:  {version}"""

  info(msg)

  nvgInit(getProcAddress)
  let vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

  koi.init(vg, getProcAddress)

  a.win = win
  a.vg = vg

# }}}
# {{{ initPaths()
proc initPaths(a) =
  alias(p, a.paths)

  const ImagesDir = "Images"

  p.appDir = getAppDir()

  const ConfigDir = "Config"
  let portableMode = dirExists(p.appDir / ConfigDir)

  let resourcesDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      normalizedPath(p.appDir / ".." / "Resources")
    else:
      p.appDir

  p.dataDir   = resourcesDir / "Data"
  p.manualDir = resourcesDir / "Manual"
  p.themesDir = resourcesDir / "Themes"
  p.themeImagesDir = p.themesDir / ImagesDir

  p.userDataDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      getHomeDir() / "Library/Application Support/Gridmonger"
    else:
      getConfigDir() / "Gridmonger"

  p.configDir = p.userDataDir / ConfigDir
  p.configFile = p.configDir / "gridmonger.cfg"

  p.logDir = p.userDataDir / "Logs"
  p.logFile = p.logDir / "gridmonger.log"

  p.autosaveDir = p.userDataDir / "Autosaves"

  p.userThemesDir = p.userDataDir / "User Themes"
  p.userThemeImagesDir = p.userThemesDir / ImagesDir

# }}}
# {{{ createDirs()
proc createDirs(a) =
  alias(p, a.paths)

  createDir(p.userDataDir)
  createDir(p.configDir)
  createDir(p.logDir)
  createDir(p.autosaveDir)
  createDir(p.userThemesDir)
  createDir(p.userThemeImagesDir)

# }}}
# {{{ initPreferences()
proc initPreferences(cfg: HoconNode; a) =
  let prefs = cfg.getObjectOrEmpty("preferences")

  with a.prefs:
    showSplash        = prefs.getBoolOrDefault("splash.show-at-startup", true)

    autoCloseSplash   = prefs.getBoolOrDefault("splash.auto-close", false)

    splashTimeoutSecs = prefs.getNaturalOrDefault(
                          "splash.auto-close-timeout-secs", 3
                        ).limit(SplashTimeoutSecsLimits)

    loadLastMap       = prefs.getBoolOrDefault("load-last-map", true)
    vsync             = prefs.getBoolOrDefault("video.vsync", true)

    autosave          = prefs.getBoolOrDefault("auto-save.enabled", true)

    autosaveFreqMins  = prefs.getNaturalOrDefault("auto-save.frequency-mins", 2)
                             .limit(AutosaveFreqMinsLimits)

# }}}
# {{{ restoreUIStateFromConfig()
proc restoreUIStateFromConfig(cfg: HoconNode, a) =
  let uiCfg = cfg.getObjectOrEmpty("last-state.ui")

  with a.opts:
    showNotesPane = uiCfg.getBoolOrDefault("option.show-notes-pane", true)
    showToolsPane = uiCfg.getBoolOrDefault("option.show-tools-pane", true)
    walkMode      = uiCfg.getBoolOrDefault("option.walk-mode",       false)
    wasdMode      = uiCfg.getBoolOrDefault("option.wasd-mode",       false)

  a.ui.drawLevelParams.setZoomLevel(
    a.theme.levelStyle,
    uiCfg.getNaturalOrDefault("zoom-level", 9).limit(ZoomLevelLimits)
  )

  with a.ui.drawLevelParams:
    viewStartRow = uiCfg.getNaturalOrDefault("view-start.row", 0)
    viewStartCol = uiCfg.getNaturalOrDefault("view-start.column", 0)
    drawCellCoords = uiCfg.getBoolOrDefault("option.show-cell-coords", true)

  with a.ui.cursor:
    let currLevel = uiCfg.getNaturalOrDefault("current-level", 0)

    if currLevel > a.doc.map.levels.high:
      level = 0
      row   = 0
      col   = 0
    else:
      level = currLevel
      row   = uiCfg.getNaturalOrDefault("cursor.row",    0)
      col   = uiCfg.getNaturalOrDefault("cursor.column", 0)

# }}}
# {{{ initApp()
proc initApp(configFile: Option[string], mapFile: Option[string],
             winCfg: HoconNode; a) =

  if configFile.isSome:
    a.paths.configFile = configFile.get

  let cfg = loadAppConfigOrDefault(a.paths.configFile)
  initPreferences(cfg, a)

  loadFonts(a)
  loadAndSetIcon(a)
  setDefaultWidgetStyles(a)

  a.doc.undoManager = newUndoManager[Map, UndoStateData]()
  a.ui.drawLevelParams = newDrawLevelParams()

  buildThemeList(a)

  var themeIndex = findThemeIndex(
    cfg.getStringOrDefault("last-state.theme-name", "Default"), a
  )

  switchTheme(if themeIndex.isSome: themeIndex.get else: 0, a)

  # Init map & load last map, or map from command line
  a.doc.map = newMap("Untitled Map", game="", author="",
                     creationTime=currentLocalDatetimeString())

  let mapFileName = if mapFile.isSome: mapFile.get
                    else: cfg.getStringOrDefault("last-state.last-document", "")

  if mapFileName != "":
    discard loadMap(mapFileName, a)
  else:
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  restoreUIStateFromConfig(cfg, a)

  updateLastCursorViewCoords(a)
  
  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  a.splash.show = a.prefs.showSplash
  a.splash.t0 = getMonoTime()
  setSwapInterval(a)

  a.updateUI = true

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePre(g_app)
  a.win.renderFrameCb = proc (win: CSDWindow) = renderFrame(g_app)

  # Set window size & position
  let (_, _, maxWidth, maxHeight) = getPrimaryMonitor().workArea

  let mergedWinCfg = cfg.getObjectOrEmpty("last-state.window")
  mergedWinCfg.merge(winCfg)

  let width  = mergedWinCfg.getNaturalOrDefault("width", 700)
                           .limit(WindowWidthLimits)

  let height = mergedWinCfg.getNaturalOrDefault("height", 800)
                           .limit(WindowWidthLimits)

  var xpos = mergedWinCfg.getIntOrDefault("x-position", -1)
  if xpos < 0: xpos = (maxWidth - width) div 2

  var ypos = mergedWinCfg.getIntOrDefault("y-position", -1)
  if ypos < 0: ypos = (maxHeight - height) div 2

  a.win.size = (width.int, height.int)
  a.win.pos = (xpos, ypos)

  if mergedWinCfg.getBoolOrDefault("maximized", false):
    a.win.maximize()

  a.win.showTitleBar = mergedWinCfg.getBoolOrDefault("show-title-bar", true)

  a.win.show()

# }}}
# {{{ cleanup()
proc cleanup(a) =
  info("Exiting app...")

  koi.deinit()

  nvgDeleteContext(a.vg)
  if a.splash.vg != nil:
    nvgDeleteContext(a.splash.vg)

  a.win.glfwWin.destroy()
  if a.splash.win != nil:
    a.splash.win.destroy()

  glfw.terminate()

  info("Cleanup successful, bye!")

  if a.logFile != nil:
    a.logFile.close()

# }}}
# {{{ crashHandler() =

when not defined(DEBUG):

  proc crashHandler(e: ref Exception, a) =
    let doAutosave = a.doc.filename != ""
    var crashAutosavePath = ""

    if doAutosave:
      try:
        crashAutosavePath = autoSaveMapOnCrash(a)
      except Exception as e:
        if a.logFile != nil:
          logError(e, "Error autosaving map on crash")

    var msg = "A fatal error has occured, Gridmonger will now exit.\n\n"

    if doAutoSave:
      if crashAutosavePath == "":
        msg &= "Autosaving the map has been unsuccesful.\n\n"
      else:
        msg &= "The map has been successfully autosaved as '" &
               crashAutosavePath

    msg &= "\n\nIf the problem persists, please refer to the 'Get Involved' " &
           "section on the website."

    when not defined(DEBUG):
      discard osdialog_message(mblError, mbbOk, msg.cstring)

    if a.logFile != nil:
      logError(e, "An unexpected error has occured, exiting")

    quit(QuitFailure)

# }}}

# }}}

# {{{ main()
proc main() =
  # Multiple application instance handling
  when defined(windows):
    var serverInitOk = false
    if ipc.isAppInstanceAlreadyRunning():
      if ipc.initClient():
        if paramCount() == 0:
          ipc.sendFocusMessage()
        else:
          ipc.sendOpenFileMessage(paramStr(1))
      quit()
    else:
      serverInitOk = ipc.initServer()

    discard attachOutputToConsole()


  g_app = new AppContext
  var a = g_app

  try:
    let (configFile, mapFile, winCfg) = parseCommandLineParams()

    initPaths(a)
    createDirs(a)
    initLogger(a)

    info(FullVersionInfo)
    info(CompiledAtInfo)
    info(fmt"Paths: {a.paths}")

    initGfx(a)
    initApp(configFile, mapFile, winCfg, a)

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)

      if a.aboutLogo.logo.data == nil:
        loadAboutLogoImage(a)

      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthru = a.opts.showThemeEditor, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.opts.showThemeEditor:
          a.win.focus()

      if a.splash.win != nil:
        glfw.makeContextCurrent(a.splash.win)
        renderFrameSplash(a)
        glFlush()

      # Swap buffers
      if a.updateUI:
        glfw.swapBuffers(a.win.glfwWin)

      if a.splash.win != nil:
        glfw.swapBuffers(a.splash.win)

      handleAutoSaveMap(a)

      # Multiple application instance handling
      when defined(windows):
        if serverInitOk:
          let msg = ipc.tryReceiveMessage()
          if msg.isSome:
            let msg = msg.get
            case msg.kind
            of mkFocus:
              a.win.restore()
              a.win.focus()

            of mkOpenFile:
              closeDialog(a)
              returnToNormalMode(a)
              openMap(msg.filename, a)
              a.win.restore()
              a.win.focus()

      # Poll/wait for events
      if koi.shouldRenderNextFrame():
        glfw.pollEvents()
      else:
        glfw.waitEventsTimeout(0.1)

    cleanup(a)

  except Exception as e:
    when defined(DEBUG): raise e
    else: crashHandler(e, a)

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
