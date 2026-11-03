import 'package:pager/pager.dart';
import 'package:test/test.dart';

void main() {
  test('pages pleines', () => expect(Pager(List.generate(40, (i) => i)).pageCount, 2));
  test('charge', () async => expect((await Pager.load(() async => [1, 2, 3])).items, [1, 2, 3]));
}
