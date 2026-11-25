import 'package:flutter/material.dart';

import '../chat/communities.dart';

/// The Community tab: your communities + "New community".
class CommunityTab extends StatelessWidget {
  const CommunityTab({super.key});

  @override
  Widget build(BuildContext context) => const CommunitiesScreen(tab: true);
}
