<p align="center"><img src="logo.svg" width="600" height="300"></p>

![Version](https://img.shields.io/badge/version-0.1.dev-blue.svg) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A little lua lib to to symbolic computation, like
```
> local x = lsc.Node('symbol', 'x')
> x + x
x + x
> (x + x):reduce()
2x
> (3 * (x - 1)):expand()
3x - 3 * (-1)
```

*Documentation incoming*