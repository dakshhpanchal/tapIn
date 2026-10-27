import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/off_account/data/off_account_storage.dart';
import 'package:opennutritracker/features/off_account/data/off_contribution_service.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';
import 'package:url_launcher/url_launcher.dart';

/// Log in to, or out of, an Open Food Facts account, which lets the app add
/// missing products and send corrections. Returns when it is closed; read the
/// storage again afterwards to see whether anyone is logged in.
Future<void> showOffAccountDialog(
  BuildContext context, {
  OffAccountStorage? storage,
  OffContributionService? service,
}) => showDialog<void>(
  context: context,
  builder: (_) => OffAccountDialog(
    storage: storage ?? locator<OffAccountStorage>(),
    service: service ?? locator<OffContributionService>(),
  ),
);

class OffAccountDialog extends StatefulWidget {
  final OffAccountStorage storage;
  final OffContributionService service;

  const OffAccountDialog({
    super.key,
    required this.storage,
    required this.service,
  });

  /// Where a new account is made.
  static final signUpUri = Uri.parse(
    'https://world.openfoodfacts.org/cgi/user.pl',
  );

  @override
  State<OffAccountDialog> createState() => _OffAccountDialogState();
}

class _OffAccountDialogState extends State<OffAccountDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  OffCredentials? _current;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await widget.storage.read();
    if (!mounted) return;
    setState(() {
      _current = current;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    if (username.contains('@')) {
      setState(
        () => _error =
            'Use your username, not your email address. You can find it on '
            'your Open Food Facts profile.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final credentials = OffCredentials(username, password);
    try {
      await widget.service.verifyLogin(credentials);
      await widget.storage.save(credentials);
      if (!mounted) return;
      setState(() {
        _current = credentials;
        _password.clear();
      });
    } on OffLoginRejectedException {
      _fail('Open Food Facts did not accept that username and password.');
    } on OffUnavailableException {
      _fail('Open Food Facts is busy right now. Try again in a minute.');
    } catch (_) {
      _fail('Could not reach Open Food Facts. Check your connection.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _logOut() async {
    await widget.storage.clear();
    if (!mounted) return;
    setState(() {
      _current = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final current = _current;
    return AlertDialog(
      title: const Text('Open Food Facts account'),
      content: !_loaded
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (current != null) ...[
                    Text(
                      'Logged in as ${current.username}.',
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: Dimens.spacing8),
                    Text(
                      'You can now share products that are missing from Open Food '
                      'Facts, and send corrections. Each upload is shown to you '
                      'first and goes out under this username.',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ] else ...[
                    Text(
                      'Log in to add products that are missing from Open Food '
                      'Facts and to correct wrong data. Your password is kept '
                      'encrypted on this phone and only sent to Open Food '
                      'Facts, when you upload.',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: Dimens.spacing12),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: Dimens.spacing8),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _logIn(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        OffAccountDialog.signUpUri,
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('No account? Create one'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: Dimens.spacing8),
                    Text(
                      _error!,
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_loaded && current != null)
          TextButton(onPressed: _logOut, child: const Text('Log out'))
        else if (_loaded)
          FilledButton(
            onPressed: _busy ? null : _logIn,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log in'),
          ),
      ],
    );
  }
}
