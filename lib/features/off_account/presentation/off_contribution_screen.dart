import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/off_account/data/off_account_storage.dart';
import 'package:opennutritracker/features/off_account/data/off_contribution_service.dart';
import 'package:opennutritracker/features/off_account/presentation/off_account_dialog.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';

/// Reviews a product and sends it to Open Food Facts. Nothing leaves the phone
/// until the user presses Send, and the form says plainly that it is public.
class OffContributionScreen extends StatefulWidget {
  final OffProductSubmission initial;

  /// True when fixing a product that already exists on Open Food Facts.
  final bool isCorrection;
  final OffAccountStorage? storage;
  final OffContributionService? service;

  const OffContributionScreen({
    super.key,
    required this.initial,
    this.isCorrection = false,
    this.storage,
    this.service,
  });

  @override
  State<OffContributionScreen> createState() => _OffContributionScreenState();
}

class _OffContributionScreenState extends State<OffContributionScreen> {
  late final OffAccountStorage _storage =
      widget.storage ?? locator<OffAccountStorage>();
  late final OffContributionService _service =
      widget.service ?? locator<OffContributionService>();

  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _sending = false;
  String? _error;

  static String _fmt(double? v) {
    if (v == null) return '';
    final r = double.parse(v.toStringAsFixed(2));
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _c = {
      'name': TextEditingController(text: i.name),
      'brands': TextEditingController(text: i.brands),
      'quantity': TextEditingController(text: i.quantity),
      'serving': TextEditingController(text: i.servingSize),
      'kcal': TextEditingController(text: _fmt(i.energyKcal)),
      'fat': TextEditingController(text: _fmt(i.fat)),
      'sat': TextEditingController(text: _fmt(i.saturatedFat)),
      'carbs': TextEditingController(text: _fmt(i.carbohydrates)),
      'sugars': TextEditingController(text: _fmt(i.sugars)),
      'fiber': TextEditingController(text: _fmt(i.fiber)),
      'protein': TextEditingController(text: _fmt(i.proteins)),
      'salt': TextEditingController(text: _fmt(i.salt)),
      'comment': TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String key) {
    final t = _c[key]!.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  String? _optionalNumber(String? v) {
    final t = (v ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null || n < 0) return 'Enter a number';
    return null;
  }

  OffProductSubmission _submission() => OffProductSubmission(
    barcode: widget.initial.barcode,
    name: _c['name']!.text.trim(),
    brands: _c['brands']!.text.trim(),
    quantity: _c['quantity']!.text.trim(),
    servingSize: _c['serving']!.text.trim(),
    energyKcal: _num('kcal'),
    fat: _num('fat'),
    saturatedFat: _num('sat'),
    carbohydrates: _num('carbs'),
    sugars: _num('sugars'),
    fiber: _num('fiber'),
    proteins: _num('protein'),
    salt: _num('salt'),
  );

  /// Reasons the numbers cannot be right, so nobody publishes a typo.
  String? _plausibility(OffProductSubmission p) {
    final fat = p.fat ?? 0, carbs = p.carbohydrates ?? 0, pro = p.proteins ?? 0;
    if (carbs + fat + pro > 101) {
      return 'Carbohydrates, fat and protein add up to more than 100 g per '
          '100 g. Check the numbers.';
    }
    if ((p.sugars ?? 0) > carbs + 1) {
      return 'Sugars cannot be more than carbohydrates.';
    }
    if ((p.saturatedFat ?? 0) > fat + 1) {
      return 'Saturated fat cannot be more than total fat.';
    }
    if ((p.energyKcal ?? 0) > 900) {
      return 'Energy is above 900 kcal per 100 g, which is not possible. '
          'Check that it is per 100 g.';
    }
    return null;
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final product = _submission();
    final problem = _plausibility(product);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final credentials = await _storage.read();
    if (!mounted) return;
    if (credentials == null) {
      setState(() => _error = 'Log in to your Open Food Facts account first.');
      await showOffAccountDialog(context, storage: _storage, service: _service);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish on Open Food Facts?'),
        content: Text(
          '“${product.name}” will be public, under the username '
          '${credentials.username}, and licensed as open data. This cannot be '
          'taken back from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final note = _c['comment']!.text.trim();
      await _service.uploadProduct(
        credentials,
        product,
        comment: note.isEmpty
            ? (widget.isCorrection
                  ? 'Correction from ${AppConst.userAgentAppName}'
                  : 'Added with ${AppConst.userAgentAppName}')
            : note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to Open Food Facts. Thank you!')),
      );
      Navigator.of(context).pop(true);
    } on OffLoginRejectedException {
      _fail('Open Food Facts rejected your login. Log in again in Settings.');
    } on OffUnavailableException {
      _fail('Open Food Facts is busy right now. Try again in a minute.');
    } on OffContributionException catch (e) {
      _fail('Open Food Facts did not accept it: ${e.message}');
    } catch (_) {
      _fail('Could not reach Open Food Facts. Check your connection.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = message;
    });
  }

  Widget _field(
    String key,
    String label, {
    bool number = true,
    bool required = false,
    String? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Dimens.spacing12),
    child: TextFormField(
      controller: _c[key],
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (v) {
        if (required && (v ?? '').trim().isEmpty) return 'Required';
        return number ? _optionalNumber(v) : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isCorrection ? 'Correct on Open Food Facts' : 'Share product',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Dimens.spacing16),
          children: [
            Container(
              padding: const EdgeInsets.all(Dimens.spacing12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'This is sent to Open Food Facts, a public database anyone can '
                'use. Copy the values from the package label, per 100 g (or '
                '100 ml), and leave a field empty if the label does not list it.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Text('Barcode ${widget.initial.barcode}'),
            const SizedBox(height: Dimens.spacing12),
            _field('name', 'Product name', number: false, required: true),
            _field('brands', 'Brand', number: false),
            _field('quantity', 'Package size (e.g. 500 g)', number: false),
            _field('serving', 'Serving size (e.g. 30 g)', number: false),
            const SizedBox(height: Dimens.spacing4),
            Text(
              'Nutrition per 100 g',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimens.spacing12),
            _field('kcal', 'Energy', required: true, suffix: 'kcal'),
            _field('fat', 'Fat', suffix: 'g'),
            _field('sat', 'of which saturated', suffix: 'g'),
            _field('carbs', 'Carbohydrates', suffix: 'g'),
            _field('sugars', 'of which sugars', suffix: 'g'),
            _field('fiber', 'Fibre', suffix: 'g'),
            _field('protein', 'Protein', suffix: 'g'),
            _field('salt', 'Salt', suffix: 'g'),
            _field('comment', 'Note for reviewers (optional)', number: false),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Dimens.spacing12),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: const Text('Review and send'),
            ),
          ],
        ),
      ),
    );
  }
}
