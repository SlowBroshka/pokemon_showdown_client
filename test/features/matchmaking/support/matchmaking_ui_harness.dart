import 'package:pokemon_showdown_client/core/matchmaking/formats/format_catalog_controller.dart';
import 'package:pokemon_showdown_client/features/matchmaking/matchmaking_controller.dart';

import '../../auth/support/auth_ui_harness.dart';

final class MatchmakingUiHarness {
  MatchmakingUiHarness() {
    catalog = FormatCatalogController(session: account.session);
    search = MatchmakingController(
      session: account.session,
      auth: account.auth,
      catalog: catalog,
      rooms: account.connection.rooms,
    );
  }

  final account = AuthUiHarness();
  late final FormatCatalogController catalog;
  late final MatchmakingController search;

  Future<void> dispose() async {
    await search.dispose();
    await catalog.dispose();
    await account.dispose();
  }
}
