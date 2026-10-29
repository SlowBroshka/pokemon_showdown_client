import 'package:flutter/material.dart';

import '../../core/transport/transport_status.dart';
import '../../core/auth/auth_controller.dart';
import '../auth/auth_panel.dart';
import '../battle/battle_panel.dart';
import '../matchmaking/matchmaking_controller.dart';
import '../matchmaking/matchmaking_panel.dart';
import 'connection_controller.dart';
import '../../l10n/app_localizations.dart';
import 'connection_message_localization.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    this.controller,
    this.authController,
    this.matchmakingController,
  }) : assert(authController == null || controller != null),
       assert(
         matchmakingController == null ||
             (controller != null && authController != null),
       );
  final ConnectionController? controller;
  final AuthController? authController;
  final MatchmakingController? matchmakingController;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final ConnectionController _controller;
  final _endpoint = TextEditingController(
    text: ConnectionController.defaultEndpoint,
  );
  final _roomId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ConnectionController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _endpoint.dispose();
    _roomId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final status = _controller.status;
            final room = _controller.room;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      l10n.connectionHeading,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.connectionDescription),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _endpoint,
                      enabled: _controller.canConnect,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.serverAddress,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _controller.connect(_endpoint.text),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(switch (status) {
                        TransportStatus.connecting => l10n.statusConnecting,
                        TransportStatus.connected => l10n.statusConnected,
                        _ => l10n.statusDisconnected,
                      }),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _controller.canConnect
                              ? () => _controller.connect(_endpoint.text)
                              : null,
                          child: Text(l10n.connect),
                        ),
                        OutlinedButton(
                          onPressed:
                              !_controller.disconnecting &&
                                  (status == TransportStatus.connecting ||
                                      status == TransportStatus.connected)
                              ? _controller.disconnect
                              : null,
                          child: Text(
                            status == TransportStatus.connecting
                                ? l10n.cancel
                                : l10n.disconnect,
                          ),
                        ),
                      ],
                    ),
                    if (_controller.error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          localizeConnectionMessage(_controller.error!, l10n),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    if (widget.authController != null) ...[
                      AuthPanel(
                        controller: widget.authController!,
                        onDisconnect: _controller.disconnect,
                      ),
                      const Divider(height: 32),
                    ],
                    if (widget.matchmakingController != null) ...[
                      MatchmakingPanel(
                        controller: widget.matchmakingController!,
                        onDisconnect: _controller.disconnect,
                      ),
                      const Divider(height: 32),
                    ],
                    Text(
                      l10n.roomHeading,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (room == null) ...[
                      TextField(
                        controller: _roomId,
                        enabled: _controller.canJoin,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.roomIdLabel,
                          hintText: l10n.roomIdHint,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _controller.join(_roomId.text),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: _controller.canJoin
                              ? () => _controller.join(_roomId.text)
                              : null,
                          child: Text(l10n.join),
                        ),
                      ),
                      if (_controller.joiningId != null)
                        Text(l10n.awaitingJoin)
                      else
                        Text(l10n.noActiveRoom),
                    ] else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.title ?? room.id,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(l10n.roomIdValue(room.id)),
                              Text(l10n.roomType(room.type)),
                              if (room.isStale) Text(l10n.staleRoom),
                              if (_controller.leaving) Text(l10n.awaitingLeave),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _controller.canLeave
                                    ? _controller.leave
                                    : null,
                                child: Text(l10n.leaveRoom),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_controller.battle case final battle?)
                      BattlePanel(key: ObjectKey(battle), controller: battle),
                    const Divider(height: 32),
                    Text(
                      l10n.noticesHeading,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_controller.notices.isEmpty) Text(l10n.noNotices),
                    for (final notice in _controller.notices)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(localizeConnectionMessage(notice, l10n)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
