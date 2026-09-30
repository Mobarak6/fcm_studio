/// The package list for a phone (spec §9.2): the last packages used on it
/// first, then the rest sorted, filtered by [query] (ignoring case).
List<String> orderPackages(
  List<String> installed,
  List<String> recent,
  String query,
) {
  final text = query.trim().toLowerCase();
  bool matches(String package) =>
      text.isEmpty || package.toLowerCase().contains(text);
  final installedSet = installed.toSet();
  final first = [
    for (final package in recent)
      if (installedSet.contains(package) && matches(package)) package,
  ];
  final rest = [
    for (final package in installed)
      if (!first.contains(package) && matches(package)) package,
  ]..sort();
  return [...first, ...rest];
}
