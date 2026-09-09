import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../lab/schedule_tab.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            ModeHeader(
              mode: 'HORARIO',
              subtitle: 'FLIGHT · SEMANA ACADÉMICA',
              color: yFlight,
              onBack: () => Navigator.pop(context),
            ),
            const Expanded(child: ScheduleTab()),
          ],
        ),
      ),
    );
  }
}
