---
title: "photo_manager_image_provider 的兼容性"
weight: 1
# geekdocFlatSection: false
# geekdocToc: 6
# geekdocHidden: false
---

photo_manager_image_provider 版本的选择取决于 flutter 版本和 photo_manager 版本。

| image_provider | flutter | photo_manager |
| :---: | :---: | :---: |
| ^1.0.0 | ">=2.13.0 <3.14.0" | ^2.6.0 |
| ^2.0.0 | ^3.14.0 | ^2.6.0 |

## 更新日志

这里指的是 flutter 的版本

### 3.14.0

Flutter 的这个 [提交（3.14.0）][remove-load] 移除了 `ImageStreamCompleter.load`。

从 flutter 3.14.0 开始, 请使用 `photo_manager_image_provider` 的 2.x 版本。

[remove-load]: https://github.com/flutter/flutter/commit/b4f4ece40d956ad86efa340ff7fe9d0fa6deea07
