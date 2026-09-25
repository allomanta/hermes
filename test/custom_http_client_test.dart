// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/utils/custom_http_client.dart';
import 'package:http/http.dart' as http;

class _PendingClient extends http.BaseClient {
  final pending = Completer<http.StreamedResponse>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      pending.future;

  @override
  void close() => closed = true;
}

void main() {
  test('a request cannot wait forever for response headers', () async {
    final pending = _PendingClient();
    final client = ResponseHeaderTimeoutClient(
      pending,
      const Duration(milliseconds: 10),
    );

    await expectLater(
      client.send(http.Request('GET', Uri.parse('https://example.org/sync'))),
      throwsA(isA<TimeoutException>()),
    );
    client.close();
    expect(pending.closed, isTrue);
  });
}
