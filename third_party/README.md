# Third-party IP libraries

## Digilent Vivado library

- Bundled directory: [`vivado-library`](vivado-library).
- Upstream: <https://github.com/Digilent/vivado-library>.
- This snapshot was copied from `D:/Vivado_IDE/lib/vivado-library-master`
  on 2026-11-05. The source directory contains no Git metadata, so its upstream
  commit is unknown. The copy preserves the source files without modification.
- Windows `Thumbs.db` files and Vivado `.Xil` lock files are excluded from Git.
  Shipped IP sources are retained even where the upstream ignore rules match them.
- Original license: [`vivado-library/License.txt`](vivado-library/License.txt),
  MIT, Copyright (c) 2017 Digilent. Additional notices in individual files and
  subdirectories are retained and apply to those components.

The active Vivado project references `$PPRDIR/../third_party/vivado-library`.
After cloning, refresh the IP catalog and regenerate the block design output
products. No submodule initialization or separate library download is needed.

If setting the repository manually in Vivado, choose this checkout's
`third_party/vivado-library` directory in **Settings → IP → Repository**.
Keep the whole library directory together, including `ip`, `if`, `module`
and license files.
