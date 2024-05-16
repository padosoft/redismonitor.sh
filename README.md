
# redismonitor.sh
Bash script to check your redis is up and used memory is under %. 

[![Software License][ico-license]](LICENSE.md)

Table of Contents
=================

  * [redismonitor.sh](#redismonitor.sh)
  * [Table of Contents](#table-of-contents)
  * [Prerequisites](#prerequisites)
  * [Install](#install)
  * [Usage](#usage)
  * [Example](#example)
  * [Contributing](#contributing)
  * [Credits](#credits)
  * [About Padosoft](#about-padosoft)
  * [License](#license)

# Prerequisites

bash

# Install

This package can be installed easy.

``` bash
cd /root/myscript
git clone https://github.com/padosoft/redismonitor.sh.git
cd redismonitor.sh
chmod +x redismonitor.sh
```


If you want to set your value and override default var values create a redismonitor.config file by coping the given template redismonitor.config.template, 
open in your favorite editor and make changes:

``` bash
cp /root/myscript/redismonitor.sh/redismonitor.config.template /root/myscript/redismonitor.sh/redismonitor.config 

nano /root/myscript/redismonitor.sh/redismonitor.config
```


If you want to run programmatically, add it to cronjobs manually or execute install script:

``` bash
cd /root/myscript/redismonitor.sh
chmod +x install.sh
bash install.sh
```


# Usage
``` bash
bash redismonitor.sh
```

## Example
``` bash
bash redismonitor.sh
```
For help:
``` bash
bash redismonitor.sh
```

# Contributing

Please see [CONTRIBUTING](CONTRIBUTING.md) and [CONDUCT](CONDUCT.md) for details.


# Credits

- [Lorenzo Padovani](https://github.com/lopadova)
- [Padosoft](https://github.com/padosoft)
- [All Contributors](../../contributors)

# About Padosoft
Padosoft is a software house based in Florence, Italy. Specialized in E-commerce and web sites.

# License

The MIT License (MIT). Please see [License File](LICENSE.md) for more information.

[ico-license]: https://img.shields.io/badge/License-GPL%20v3-blue.svg?style=flat-square
