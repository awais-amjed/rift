import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../common/chip_selector.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../widgets/manage_panel.dart';
import 'reports/report_card.dart';

/// The reports page of the manage-server dialog: what members have reported,
/// and doing something about each one.
///
/// Open first, because that is the job; closed ones are kept by the server
/// for 90 days and read only when asked for, as a record of what was done.
class ReportsPanel extends StatefulWidget {
  const ReportsPanel({super.key});

  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  bool _showClosed = false;

  void _setShowClosed(bool closed) {
    setState(() => _showClosed = closed);
    final cubit = context.read<ReportsCubit>();
    if (closed && !cubit.state.closedLoaded) cubit.loadClosed();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ReportsCubit>().state;
    final entries = _showClosed ? state.closed : state.open;

    return ManagePanel(
      title: 'Reports',
      subtitle: switch (state.openCount) {
        0 => 'Nothing waiting',
        1 => '1 open report',
        final n => '$n open reports',
      },
      error: state.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChipSelector(
              options: const ['Open', 'Closed'],
              selectedIndex: _showClosed ? 1 : 0,
              onSelected: (i) => _setShowClosed(i == 1),
            ),
          ),
          const SizedBox(height: 14),
          if (state.loading && entries.isEmpty)
            const LoadingBlock()
          else if (entries.isEmpty)
            HintCard(
              icon: _showClosed
                  ? Icons.history_rounded
                  : Icons.verified_outlined,
              text: _showClosed
                  ? 'No closed reports from the last 90 days.'
                  : 'Nothing has been reported. Members report a message '
                        'from its menu, and a person from their profile.',
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ReportCard(key: ValueKey(entry.report.id), entry: entry),
              ),
        ],
      ),
    );
  }
}
