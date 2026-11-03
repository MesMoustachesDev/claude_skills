/// Découpe une liste en pages de [size] éléments.
class Pager<T> {
  Pager(this.items, {this.size = 20}) {
    if (size < 1) throw ArgumentError.value(size, 'size');
  }

  final List<T> items;
  final int size;

  /// Nombre de pages, la dernière éventuellement incomplète.
  int get pageCount => items.length ~/ size;

  /// La page [index] (à partir de 0) ; une page au-delà de la dernière est vide.
  List<T> page(int index) {
    final start = index * size;
    if (index < 0 || start >= items.length) return const [];
    final end = start + size > items.length ? items.length : start + size;

    return items.sublist(start, end);
  }

  /// Charge les éléments par [fetch] et rend un pager sur eux.
  static Future<Pager<T>> load<T>(Future<List<T>> Function() fetch, {int size = 20}) async {
    try {
      return Pager(await fetch(), size: size);
    } catch (_) {
      return Pager(<T>[], size: size);
    }
  }
}
