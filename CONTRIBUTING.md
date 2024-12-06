# Contributing to Plugins

We welcome contributions to this project in the form of pull requests, issues, or general feedback and bug reports.

## For issues and bugs

All bugs or features will help project to be better, so please report bugs to us.

Please file issues and bugs using the [issue tracker][issue_tracker].

### Before you report a bug

- **Search issue tracker first.** You may find that someone else already reported your problem.
- **Check the Changelog.** You may find that the bug is already fixed in the git version, but it just hasn't been released yet.

If you can not find the same issue, please provide the following information:

- Provide `flutter doctor -v` output.
- Provide the photo_manager version.
- Provide the plugin name and version.

## Pull requests

We welcome pull requests through [Github][pull_requests].

### New features for existing plugins

If you want to add new features for existing plugins, please create a new issue and describe your feature.
After the discussion, provide a pull request.

### New plugins

If you want to add new plugins, please create a new issue and describe your plugin.
After the discussion, provide a pull request.

### Fix bug

If you want to fix bug, please create a new issue and describe your bug.
If you can provide a pull request, that will be better.

## How to develop the plugins

1. Clone the repo, and submodules.

```bash
git clone https://github.com/fluttercandies/flutter_photo_manager_plugins.git
cd flutter_photo_manager_plugins
git submodule update --init --recursive
```

1. Install [melos][].

```bash
dart pub global activate melos
```

1. Run `melos bootstrap` to install dependencies.

```bash
melos bootstrap
```

## Compatibility

If some plugin is developed for a specific version of flutter/photo_manager,
please add the compatibility to the `pubspec.yaml` of the plugin,
and change docs, the code need open a new branch and named as `<plugin_name>-<version>`.

## For admin of this repo

1. Run `melos run cp_files` to copy the LICENSE to all plugins.

```bash
melos run cp_files
```

1. Run `melos publish` to publish the plugins.
2. Or run `./publish.sh` to publish the plugins.

Now, we can use CI to publish the plugins.

[issue_tracker]: https://github.com/fluttercandies/flutter_photo_manager_plugins/issues
[pull_requests]: https://github.com/fluttercandies/flutter_photo_manager_plugins/pulls
[melos]: https://pub.dev/packages/melos
