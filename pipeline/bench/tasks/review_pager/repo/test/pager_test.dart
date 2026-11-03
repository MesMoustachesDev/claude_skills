import 'package:pager/pager.dart';
import 'package:test/test.dart';

void main() {
  test('première page', () => expect(Pager(List.generate(45, (i) => i)).page(0).length, 20));
  test('au-delà de la fin, vide', () => expect(Pager([1, 2]).page(3), isEmpty));
}
