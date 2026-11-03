/// Une ligne du panier.
class Line {
  const Line(this.sku, this.unitCents, this.quantity);

  final String sku;
  final int unitCents;
  final int quantity;
}

/// Erreurs du panier.
class CartError implements Exception {
  const CartError(this.message);

  final String message;

  @override
  String toString() => 'CartError: $message';
}

/// Un panier : lignes par SKU, total en centimes, remise par code.
///
/// Règles (spec) :
/// - `add` d'un SKU déjà présent cumule la quantité ; quantité ≤ 0 → CartError ;
/// - une ligne ne dépasse jamais 99 unités → CartError, le panier inchangé ;
/// - `remove` d'un SKU absent → CartError ;
/// - `total` = somme des lignes ; code `TEN` : −10 % arrondi au centime inférieur de la remise,
///   seulement à partir de 50,00 € ; code `SHIP` : −4,90 € si le total dépasse 30,00 €, jamais
///   sous zéro ; un code inconnu → CartError ; un seul code à la fois (le dernier gagne).
class Cart {
  List<Line> get lines => throw UnimplementedError();

  void add(String sku, int unitCents, int quantity) => throw UnimplementedError();

  void remove(String sku) => throw UnimplementedError();

  void apply(String code) => throw UnimplementedError();

  int get totalCents => throw UnimplementedError();
}
