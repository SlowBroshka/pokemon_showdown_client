import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import 'auth_message_localization.dart';

/// View only. The app owns the shared controller and connection.
class AuthPanel extends StatefulWidget {
  const AuthPanel({
    super.key,
    required this.controller,
    required this.onDisconnect,
  });

  final AuthController controller;
  final Future<void> Function() onDisconnect;

  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late StreamSubscription<AuthState> _subscription;
  bool _obscure = true;
  bool _cancelling = false;
  bool _disconnecting = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.controller.changes.listen((state) {
      if (!mounted) return;
      if (state.phase != AuthPhase.ready) {
        _password.clear();
        _obscure = true;
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AuthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription.cancel());
      _username.clear();
      _password.clear();
      _obscure = true;
      _subscribe();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.controller.canLogin ||
        _username.text.trim().isEmpty ||
        _password.text.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    unawaited(
      widget.controller.login(
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
    _password.clear();
    setState(() => _obscure = true);
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _password.clear();
    await widget.controller.cancel();
    if (mounted) setState(() => _cancelling = false);
  }

  Future<void> _signOut() async {
    if (_disconnecting) return;
    setState(() => _disconnecting = true);
    _password.clear();
    _username.clear();
    await widget.onDisconnect();
    if (mounted) setState(() => _disconnecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.controller.state;
    final authenticated = state.phase == AuthPhase.authenticated;
    final busy =
        state.phase == AuthPhase.authenticating ||
        state.phase == AuthPhase.awaitingConfirmation;
    final editable = widget.controller.canLogin && !_cancelling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.authHeading, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(localizeAuthPhase(state, l10n)),
        ),
        if (!authenticated) ...[
          const SizedBox(height: 8),
          Text(l10n.authDescription),
          const SizedBox(height: 12),
          TextField(
            key: const Key('auth.username'),
            controller: _username,
            enabled: editable,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.authUsername,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('auth.password'),
            controller: _password,
            enabled: editable,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.authPassword,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('auth.togglePassword'),
                tooltip: _obscure
                    ? l10n.authShowPassword
                    : l10n.authHidePassword,
                onPressed: editable
                    ? () => setState(() => _obscure = !_obscure)
                    : null,
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('auth.submit'),
                onPressed:
                    editable &&
                        _username.text.trim().isNotEmpty &&
                        _password.text.isNotEmpty
                    ? _submit
                    : null,
                child: Text(l10n.authSignIn),
              ),
              if (busy)
                OutlinedButton(
                  key: const Key('auth.cancel'),
                  onPressed: _cancelling ? null : _cancel,
                  child: Text(l10n.authCancelSignIn),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('auth.signOut'),
            onPressed: _disconnecting ? null : _signOut,
            child: Text(l10n.authSignOut),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              localizeAuthFailure(state.error!, l10n),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
