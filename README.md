# LinuxPermissionHelp

Useful Python3 scripts for getting  a quick reference of file/directory permissions for mainly begineers but also just generally useful.

## perms

Help menu:

```bash
usage: perms [-h] [-u UMASK] [-c] [-i PATH] [--reference]
             [permissions]

Enhanced Linux Permissions & File Info Utility

positional arguments:
  permissions        Octal (e.g. 755) or symbolic (e.g. rwxr-xr-x)
                     permission

options:
  -h, --help         show this help message and exit
  -u, --umask UMASK  Explain umask (e.g. 022)
  -c, --chattr       Show chattr attributes table
  -i, --path PATH    Inspect file/directory metadata & chattr
  --reference        Show reference tables for chmod, umask, chattr
                     with examples
```

## chmod-calc

Help menu:

```bash
usage: chmod-calc [-h] file

chmod‑calculator – display permissions, type and attributes of a file
using a tidy tabular layout.

positional arguments:
  file        Path to the file to analyze.

options:
  -h, --help  show this help message and exit
```



