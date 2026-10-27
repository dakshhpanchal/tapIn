import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/ont_http_client.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/off_account/data/off_account_storage.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';

/// The login was refused: wrong username or password.
class OffLoginRejectedException implements Exception {
  const OffLoginRejectedException();
  @override
  String toString() => 'OffLoginRejectedException';
}

/// Open Food Facts took the request but did not accept the product.
class OffContributionException implements Exception {
  final String message;
  const OffContributionException(this.message);
  @override
  String toString() => 'OffContributionException($message)';
}

/// A product, as the per-100 g label facts Open Food Facts keeps.
class OffProductSubmission {
  final String barcode;
  final String name;
  final String brands;
  final String quantity; // "500 g"
  final String servingSize; // "30 g"

  // Per 100 g (or 100 ml); all optional except energy, which the form asks for.
  final double? energyKcal;
  final double? fat;
  final double? saturatedFat;
  final double? carbohydrates;
  final double? sugars;
  final double? fiber;
  final double? proteins;
  final double? salt; // grams

  const OffProductSubmission({
    required this.barcode,
    required this.name,
    this.brands = '',
    this.quantity = '',
    this.servingSize = '',
    this.energyKcal,
    this.fat,
    this.saturatedFat,
    this.carbohydrates,
    this.sugars,
    this.fiber,
    this.proteins,
    this.salt,
  });

  /// The submission for [meal], per 100 g, for the user to review and send.
  factory OffProductSubmission.fromMeal(MealEntity meal) {
    String withUnit(String? amount, String? unit) {
      final number = double.tryParse((amount ?? '').trim());
      if (number == null || number <= 0) return '';
      final label = switch (unit) {
        'g' => 'g',
        'ml' => 'ml',
        _ => '',
      };
      return label.isEmpty ? '' : '${_number(number)} $label';
    }

    final n = meal.nutriments;
    final sodiumMg = n.sodium100;
    return OffProductSubmission(
      barcode: meal.code ?? '',
      name: meal.name ?? '',
      brands: meal.brands ?? '',
      quantity: withUnit(meal.mealQuantity, meal.mealUnit),
      servingSize: (meal.servingSize ?? '').trim().isNotEmpty
          ? meal.servingSize!.trim()
          : withUnit('${meal.servingQuantity ?? ''}', meal.servingUnit),
      energyKcal: n.energyKcal100,
      fat: n.fat100,
      saturatedFat: n.saturatedFat100,
      carbohydrates: n.carbohydrates100,
      sugars: n.sugars100,
      fiber: n.fiber100,
      proteins: n.proteins100,
      // Salt is sodium x 2.5, and sodium is kept in mg.
      salt: sodiumMg == null ? null : sodiumMg / 1000 * 2.5,
    );
  }

  static String _number(double v) {
    final text = v.toStringAsFixed(3);
    return text.contains('.')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
  }

  /// The form fields Open Food Facts' `product_jqm2.pl` takes, without the
  /// credentials. Only what was filled in is sent, so editing a product never
  /// blanks a field the user left empty.
  Map<String, String> toFields({
    required String language,
    required String appVersion,
    required String comment,
  }) {
    final fields = <String, String>{
      'code': barcode,
      'lc': language,
      'product_name': name.trim(),
      'nutrition_data_per': '100g',
      'app_name': AppConst.userAgentAppName,
      'app_version': appVersion,
      'comment': comment,
    };
    void text(String key, String value) {
      if (value.trim().isNotEmpty) fields[key] = value.trim();
    }

    void nutrient(String id, double? value, String unit) {
      if (value == null) return;
      fields['nutriment_$id'] = _number(value);
      fields['nutriment_${id}_unit'] = unit;
    }

    text('brands', brands);
    text('quantity', quantity);
    text('serving_size', servingSize);
    nutrient('energy-kcal', energyKcal, 'kcal');
    nutrient('fat', fat, 'g');
    nutrient('saturated-fat', saturatedFat, 'g');
    nutrient('carbohydrates', carbohydrates, 'g');
    nutrient('sugars', sugars, 'g');
    nutrient('fiber', fiber, 'g');
    nutrient('proteins', proteins, 'g');
    nutrient('salt', salt, 'g');
    return fields;
  }
}

/// Logs in to Open Food Facts and sends products to it.
///
/// Uploads go to the public database under the user's own account, so the app
/// only ever calls [uploadProduct] from a button the user pressed after seeing
/// what will be sent. The password travels in the body of an HTTPS POST (never
/// in a URL) and is not logged or put into any error.
class OffContributionService {
  static final _log = Logger('OffContributionService');
  static const _host = 'world.openfoodfacts.org';
  static const _timeout = Duration(seconds: 30);

  final http.Client Function() _clientFactory;
  final Future<String> Function() _userAgent;
  final Future<String> Function() _appVersion;

  OffContributionService({
    http.Client Function()? clientFactory,
    Future<String> Function()? userAgent,
    Future<String> Function()? appVersion,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _userAgent = userAgent ?? AppConst.getUserAgentString,
       _appVersion = appVersion ?? AppConst.getVersionNumber;

  Future<http.Response> _post(String path, Map<String, String> fields) async {
    final client = ONTHttpClient(await _userAgent(), _clientFactory());
    try {
      final request = http.MultipartRequest('POST', Uri.https(_host, path))
        ..fields.addAll(fields);
      final streamed = await client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  /// Throws the right exception for a busy or refusing server, else returns.
  void _checkStatus(http.Response response) {
    final code = response.statusCode;
    if (code == 401 || code == 403) throw const OffLoginRejectedException();
    if (OffUnavailableException.isUnavailable(code)) {
      throw OffUnavailableException(
        code,
        retryAfter: OffUnavailableException.parseRetryAfter(
          response.headers['retry-after'],
        ),
      );
    }
  }

  /// Checks a username and password by logging in. Returns normally when
  /// Open Food Facts accepts them (a session is started, which is not kept);
  /// throws [OffLoginRejectedException] when it refuses them.
  Future<void> verifyLogin(OffCredentials credentials) async {
    final response = await _post('/cgi/session.pl', {
      'user_id': credentials.username,
      'password': credentials.password,
    });
    _checkStatus(response);
    final cookie = response.headers['set-cookie'] ?? '';
    if (response.statusCode != 200 || !cookie.contains('session=')) {
      throw const OffLoginRejectedException();
    }
  }

  /// Adds the product to Open Food Facts, or edits it if the barcode exists.
  Future<void> uploadProduct(
    OffCredentials credentials,
    OffProductSubmission product, {
    required String comment,
    String language = 'en',
  }) async {
    final fields =
        product.toFields(
          language: language,
          appVersion: await _appVersion(),
          comment: comment,
        )..addAll({
          'user_id': credentials.username,
          'password': credentials.password,
        });
    final response = await _post('/cgi/product_jqm2.pl', fields);
    _checkStatus(response);
    if (response.statusCode != 200) {
      throw OffContributionException('HTTP ${response.statusCode}');
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const OffContributionException('Unexpected answer');
    }
    final ok = body is Map && body['status'] == 1;
    if (!ok) {
      final reason = body is Map ? '${body['status_verbose'] ?? ''}' : '';
      _log.warning('Open Food Facts did not accept the product: $reason');
      throw OffContributionException(
        reason.isEmpty ? 'The product was not accepted' : reason,
      );
    }
  }
}
