import options
import strutils
import tables

import common
import utils


using
  r: Regions
  vr: var Regions

# {{{ initRegions*()
proc initRegions*(): Regions =
  result = initTable[RegionCoords, Region]()

# }}}
# {{{ dump*()
proc dump*(r) =
  for k,v in r:
    echo "key: ", k, ", val: ", v
  echo ""

# }}}

# {{{ setRegion*()
proc setRegion*(vr; rc: RegionCoords, region: Region) =
  vr[rc] = region

# }}}
# {{{ getRegion*()
proc getRegion*(r; rc: RegionCoords): Option[Region] =
  if r.hasKey(rc): r[rc].some
  else: Region.none

# }}}
# {{{ allRegions*()
iterator allRegions*(r): (RegionCoords, Region) =
  for rc, r in r:
    yield (rc, r)

# }}}
# {{{ numRegions*()
proc numRegions*(r): Natural = r.len

# }}}
# {{{ regionNames*()
proc regionNames*(r): seq[string] =
  result = @[]
  for r in r.values:
    result.add(r.name)

# }}}

# {{{ findFirstRegionByName*()
proc findFirstRegionByName*(r; name: string): Option[(RegionCoords, Region)] =
  for rc, r in r:
    if r.name == name:
      return (rc, r).some
  result = (RegionCoords, Region).none

# }}}
# {{{ isUntitledRegion*()
const UntitledRegionPrefix = "Untitled Region "

proc isUntitledRegion*(r: Region): bool =
  r.name.startsWith(UntitledRegionPrefix)

# }}}
# {{{ nextUntitledRegionName*()
proc nextUntitledRegionName*(r; index: var int): string =
  while true:
    let name = UntitledRegionPrefix & $index
    inc(index)
    var region = r.findFirstRegionByName(name)
    if region.isNone: return name

# }}}

# vim: et:ts=2:sw=2:fdm=marker
