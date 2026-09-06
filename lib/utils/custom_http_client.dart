// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:hermes/config/isrg_x1.dart';
import 'package:hermes/config/isrg_x2.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart' as retry;
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/config/isrg_x1.dart';

/// Custom Client to add an additional certificate. This is for the isrg X1
/// certificate which is needed for LetsEncrypt certificates. It is shipped
/// on Android since OS version 7.1. As long as we support older versions we
/// still have to ship this certificate by ourself.
class CustomHttpClient {
  static HttpClient customHttpClient() {
    final context = SecurityContext.defaultContext;

    try {
      context.setTrustedCertificatesBytes(utf8.encode(ISRG_X1));
      context.setTrustedCertificatesBytes(utf8.encode(ISRG_X2));
    } on TlsException catch (e) {
      if (e.osError != null &&
          e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
      } else {
        rethrow;
      }
    }

    return HttpClient(context: context);
  }

  static http.Client createHTTPClient() => retry.RetryClient(
    PlatformInfos.isAndroid ? IOClient(customHttpClient()) : http.Client(),
  );
}
