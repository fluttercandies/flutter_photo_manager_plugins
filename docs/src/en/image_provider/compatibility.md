---
title: "compatibility of photo_manager_image_provider"
weight: 1
# geekdocFlatSection: false
# geekdocToc: 6
# geekdocHidden: false
---

The [commit][remove-load] of flutter remove `ImageStreamCompleter.load` method.

Since flutter 3.14.0, the `photo_manager_image_provider` need use 2.0.0 version.

| image_provider | flutter | photo_manager |
| :---: | :---: | :---: |
| ^1.0.0 | ">=2.0.0 <3.14.0" | ^2.0.0 |
| ^2.0.0 | ^3.14.0 | ^2.0.0 |

[remove-load]: https://github.com/flutter/flutter/commit/b4f4ece40d956ad86efa340ff7fe9d0fa6deea07
