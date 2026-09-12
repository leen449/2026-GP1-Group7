import 'package:flutter/material.dart';

import 'add_damage_screen.dart';

/// Single call site for entering the assessment-editing workflow, used by
/// both the Case Review screen's edit/pencil icon and the Claim Details
/// screen's Accept-claim action — so both paths open the exact same screen
/// through the exact same navigation call rather than two independent copies.
///
/// `AddDamageScreen` itself is pre-existing, unfinished work (its backend
/// endpoint does not exist yet) and is used here completely as-is.
class AdminNavigation {
  AdminNavigation._();

  static Future<void> openAddDamage(BuildContext context, String caseId) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddDamageScreen(caseId: caseId)),
    );
  }
}
