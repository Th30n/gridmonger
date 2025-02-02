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
`gridmonger` branch in `nim-glfw`, then install both with `nimble develop` for
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

Run `nim help` for the full list of build tasks.


### Building the manual & website

The [website](https://gridmonger.johnnovak.net) (GitHub Pages site) and
[manual](https://gridmonger.johnnovak.net/manual/contents.html) are generated
from [Sphinx](https://www.sphinx-doc.org) sources.

The website is published from the `/docs` directory in the `master` branch.

#### Requirements

- [Sphinx](https://www.sphinx-doc.org/en/master/usage/installation.html) 5.3+
- [Sass](https://sass-lang.com/) 1.37+
- [Make](https://www.gnu.org/software/make/) 3.8+
- [GNU sed](https://www.gnu.org/software/sed/) 4.8+
- Zip 3.0+


#### Building

- To build the website, run `nim site`

- To build the manual, run `nim manual`

- To create the zipped distribution package of the manual from the generated
  files, run `nim packageManual`


#### Theme development

You can run `make watch_docs_css` or `make watch_frontpage_css` from the
`sphinx-doc` directory to regenerate the CSS when the SASS files are changed
during theme development.


### Packaging & release process

See [RELEASE.md](/RELEASE.md)


## License

Developed by John Novak <<john@johnnovak.net>>, 2020-2022

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

