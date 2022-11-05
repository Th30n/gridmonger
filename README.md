<img src="extras/logo/logo-big-bw.png" width="100%" alt="Gridmonger" />

<p align="center"><em>Your trusty old-school cRPG mapping companion</em></p>

## Project homepage

[https://gridmonger.johnnovak.net](https://gridmonger.johnnovak.net)

## Build instructions

Requires [Nim](https://nim-lang.org/) 1.6.6+

### Dependencies

* [koi](https://github.com/johnnovak/koi)
* [nim-glfw](https://github.com/johnnovak/nim-glfw) (`gridmonger` branch)
* [nim-nanovg](https://github.com/johnnovak/nim-nanovg/)
* [nim-osdialog](https://github.com/johnnovak/nim-osdialog)
* [nim-riff](https://github.com/johnnovak/nim-riff)
* [winim](https://github.com/khchen/winim)

You can install most of the dependencies with [Nimble](https://github.com/nim-lang/nimble):

```
nimble install nanovg osdialog riff winim
```

For `koi` and `nim-glfw`, clone their Git repositories, check out the
`gridmonger` branch in `koi`, then install both with `nimble develop` for
local development.


### Compiling

Debug build (debug logging enabled, file dialogs disabled on Windows):

```
nim debug
```

Release build:

```
nim release
```

See `config.nims` for further build tasks.


### Packaging



### Documentation

The [website](https://gridmonger.johnnovak.net) and
[manual](https://gridmonger.johnnovak.net/manual/contents.html) are generated
from [Sphinx](https://www.sphinx-doc.org) sources. Please see the
https://github.com/johnnovak/gridmonger-site repo for further details.

## License

Developed by John Novak <<john@johnnovak.net>>, 2020-2022

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

