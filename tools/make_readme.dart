import 'dart:io';
import 'package:melos/melos.dart';
import 'package:path/path.dart' as path;

class Package {
  final String name;
  final String version;
  final String location;

  Package({
    required this.name,
    required this.version,
    required this.location,
  });

  factory Package.fromMelo(Map map) {
    return Package(
      name: map['name'],
      version: map['version'],
      location: map['location'],
    );
  }

  static List<Package> fromMeloList(List list) {
    return list.map((e) => Package.fromMelo(e)).toList();
  }

  static List<Package> fromMeloworkspace(MelosWorkspace space) {
    final result = <Package>[];
    for (final pkg in space.filteredPackages.values) {
      result.add(Package(
        name: pkg.name,
        version: pkg.version.toString(),
        location: pkg.path,
      ));
    }

    return result;
  }

  String get relativePath =>
      path.relative(location, from: Directory.current.path);

  String toMarkdown() {
    final link = '[$relativePath]($relativePath)';
    return '| $name | $version | $link |';
  }
}

final pkgs = [];

Future<void> main(List<String> args) async {
  // print('pwd: $pwd');
  // Get the version list
  final config =
      await MelosWorkspaceConfig.fromWorkspaceRoot(Directory.current);
  final melos = Melos(config: config);
  final space = await melos.createWorkspace();
  final pkgList = Package.fromMeloworkspace(space);

  final pkgListMd = '''
| Package | Version | Location |
| ------- | ------- | -------- |
${pkgList.map((e) => e.toMarkdown()).join('\n')}
'''
      .trim();

  // print(pkgListMd);

  final template = File('README.template.md').readAsStringSync();

  final readme = template.replaceFirst('<!-- PKG_LIST -->', pkgListMd);

  File('README.md').writeAsStringSync(readme);
}
