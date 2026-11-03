const _accents = {'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'à': 'a', 'â': 'a', 'ç': 'c', 'î': 'i', 'ï': 'i', 'ô': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'œ': 'oe', 'æ': 'ae'};

String slugify(String title, {int maxLength = 40}) {
  if (maxLength < 1) throw ArgumentError.value(maxLength, 'maxLength');
  final lower = title.toLowerCase().split('').join();
  final slug = lower.replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) throw ArgumentError.value(title, 'title');
  if (slug.length <= maxLength) return slug;
  final cut = slug.substring(0, maxLength + 1).lastIndexOf('-');
  return cut > 0 ? slug.substring(0, cut) : slug.substring(0, maxLength);
}
