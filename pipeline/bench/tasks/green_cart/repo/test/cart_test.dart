import 'package:cart/cart.dart';
import 'package:test/test.dart';

void main() {
  late Cart cart;
  setUp(() => cart = Cart());

  test('un panier vide vaut zéro', () => expect(cart.totalCents, 0));

  test('ajouter le même SKU cumule la quantité', () {
    cart.add('a', 250, 2);
    cart.add('a', 250, 3);
    expect(cart.lines.single.quantity, 5);
    expect(cart.totalCents, 1250);
  });

  test('une quantité nulle ou négative est refusée', () {
    expect(() => cart.add('a', 100, 0), throwsA(isA<CartError>()));
    expect(() => cart.add('a', 100, -1), throwsA(isA<CartError>()));
    expect(cart.lines, isEmpty);
  });

  test('plus de 99 unités sur une ligne est refusé, le panier inchangé', () {
    cart.add('a', 100, 98);
    expect(() => cart.add('a', 100, 2), throwsA(isA<CartError>()));
    expect(cart.lines.single.quantity, 98);
  });

  test('retirer un SKU absent est refusé', () {
    expect(() => cart.remove('x'), throwsA(isA<CartError>()));
  });

  test('retirer un SKU enlève sa ligne', () {
    cart.add('a', 100, 1);
    cart.add('b', 200, 1);
    cart.remove('a');
    expect(cart.lines.map((l) => l.sku), ['b']);
  });

  test('TEN retire 10 % à partir de 50 €, remise arrondie au centime inférieur', () {
    cart.add('a', 5005, 1);
    cart.apply('TEN');
    expect(cart.totalCents, 5005 - 500);
  });

  test('TEN ne fait rien sous 50 €', () {
    cart.add('a', 4999, 1);
    cart.apply('TEN');
    expect(cart.totalCents, 4999);
  });

  test('SHIP retire 4,90 € au-delà de 30 €', () {
    cart.add('a', 3001, 1);
    cart.apply('SHIP');
    expect(cart.totalCents, 3001 - 490);
  });

  test('SHIP ne s’applique pas à 30 € pile', () {
    cart.add('a', 3000, 1);
    cart.apply('SHIP');
    expect(cart.totalCents, 3000);
  });

  test('le dernier code gagne', () {
    cart.add('a', 6000, 1);
    cart.apply('TEN');
    cart.apply('SHIP');
    expect(cart.totalCents, 6000 - 490);
  });

  test('un code inconnu est refusé', () {
    expect(() => cart.apply('FREE'), throwsA(isA<CartError>()));
  });

  test('la remise suit le panier quand il change', () {
    cart.add('a', 6000, 1);
    cart.apply('TEN');
    cart.remove('a');
    cart.add('b', 1000, 1);
    expect(cart.totalCents, 1000);
  });

  test('les lignes ne se modifient pas de l’extérieur', () {
    cart.add('a', 100, 1);
    expect(() => cart.lines.add(const Line('b', 1, 1)), throwsUnsupportedError);
  });
}
