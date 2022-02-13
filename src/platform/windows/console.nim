import std/exitprocs

import winim


proc sendReturnKeypress() =
  let h = GetConsoleWindow()
  if IsWindow(h):
    PostMessage(h, WM_KEYUP, VK_RETURN, 0)


proc attachOutputToConsole*(): bool =
  ## Allow console output for Windows GUI applications compiled with the
  ## --app:gui flag

  if AttachConsole(AttachParentProcess) != 0:
    if GetStdHandle(StdOutputHandle) != InvalidHandleValue:
      stdout.reopen("CONOUT$", fmWrite)
    else: return

    if GetStdHandle(StdErrorHandle) != InvalidHandleValue:
      stderr.reopen("CONOUT$", fmWrite)
    else: return

    setStdIoUnbuffered()

    # Windows waits for the user to press "Enter" before releasing the
    # console after exit, so we'll simulate that here
    addExitProc(sendReturnKeypress)

    result = true

