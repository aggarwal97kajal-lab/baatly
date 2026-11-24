import 'dart:convert';

import 'package:baatly/data/e2e.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<E2E> party() async {
    final e = E2E.detached();
    await e.useKeyPair(await X25519().newKeyPair());
    return e;
  }

  test('message encrypted by A opens only for B, from A', () async {
    final a = await party(), b = await party(), eve = await party();
    final box = await a.seal({'t': 'Namaste 🙏', 'ts': 1}, b.publicKey);
    expect(box.contains('Namaste'), isFalse);
    final plain = await b.open(box, a.publicKey);
    expect(plain['t'], 'Namaste 🙏');

    // Someone else can't read it.
    await expectLater(eve.open(box, a.publicKey), throwsA(anything));
    // Can't be passed off as coming from someone else.
    await expectLater(b.open(box, eve.publicKey), throwsA(anything));
    // Tampering is detected.
    final j = jsonDecode(box) as Map<String, dynamic>;
    final c = base64Url.decode((j['c'] as String).padRight(((j['c'] as String).length + 3) ~/ 4 * 4, '='));
    c[0] ^= 1;
    j['c'] = base64Url.encode(c).replaceAll('=', '');
    await expectLater(b.open(jsonEncode(j), a.publicKey), throwsA(anything));
  });

  test('status key sealed per viewer opens the shared box', () async {
    final owner = await party(), viewer = await party();
    final (key, blob) = await owner.lock(utf8.encode('photo-bytes'));
    final sealed = await owner.seal({'k': base64Encode(key)}, viewer.publicKey);
    final k = await viewer.open(sealed, owner.publicKey);
    final clear = await viewer.unlock(blob, base64Decode(k['k'] as String));
    expect(utf8.decode(clear), 'photo-bytes');
    // Owner can open their own copy too.
    final mine = await owner.seal({'k': base64Encode(key)}, owner.publicKey);
    expect((await owner.open(mine, owner.publicKey))['k'], base64Encode(key));
  });
}
