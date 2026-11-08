import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../models/price_model.dart';
import '../utils/formatters.dart';

class SignalCard extends StatelessWidget {
  final PriceSnapshot snapshot;
  final SignalResult result;
  final DateTime Function()? now;
  const SignalCard(
      {super.key, required this.snapshot, required this.result, this.now});
  @override
  Widget build(BuildContext context) {
    final stale = snapshot.isStale((now ?? DateTime.now)());
    final isBuy = result.signal == Signal.buy;
    final paused = result.signal == Signal.paused;
    // A paused state is informational, never a trading-looking verdict card.
    final bg = paused
        ? const Color(0xFF1C1C1E)
        : isBuy
            ? const Color(0xFF073B2A)
            : const Color(0xFF3B0707);
    final border = paused
        ? Colors.white24
        : isBuy
            ? const Color(0xFF17A36B)
            : const Color(0xFFB34A4A);
    final title = paused
        ? 'SIGNALS PAUSED - ${snapshot.metal.label.toUpperCase()}'
        : '${isBuy ? "BUY" : "WAIT"} ${snapshot.metal.label.toUpperCase()} ${isBuy ? "NOW!" : ""}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withValues(alpha: 0.6), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _Fact('Price', '₹${fmt(snapshot.price)} / ${snapshot.unit}'),
          _Fact('Recent high', '₹${fmt(snapshot.recentHigh)}'),
          _Fact('Below high', '${snapshot.drawdownPct.toStringAsFixed(2)}%'),
          _Fact('Updated', timeFmt(snapshot.updatedAt)),
          _Fact('Source', snapshot.source),
        ]),
        if (stale) ...[
          const SizedBox(height: 8),
          Text('This price is stale - pull to refresh.',
              style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        Text(result.reason,
            style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Neutral card for live spot prices whose "high" is only a rolling
/// observed-since value. Shows price facts; no buy/wait verdict.
class LiveSpotCard extends StatelessWidget {
  final PriceSnapshot snapshot;
  final DateTime Function()? now;
  const LiveSpotCard({super.key, required this.snapshot, this.now});
  @override
  Widget build(BuildContext context) {
    final stale = snapshot.isStale((now ?? DateTime.now)());
    final since = snapshot.highObservedSince;
    final sinceLabel = since == null
        ? 'first check'
        : '${since.day}/${since.month}/${since.year}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Cfg.gold.withValues(alpha: 0.35), width: 1.2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            stale
                ? '${snapshot.metal.label.toUpperCase()} - LAST KNOWN (STALE)'
                : '${snapshot.metal.label.toUpperCase()} - LIVE SPOT',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _Fact('Price', '₹${fmt(snapshot.price)} / ${snapshot.unit}'),
          _Fact('High since $sinceLabel', '₹${fmt(snapshot.recentHigh)}'),
          _Fact('Below that high', '${snapshot.drawdownPct.toStringAsFixed(2)}%'),
          _Fact('Updated', timeFmt(snapshot.updatedAt)),
          _Fact('Source', snapshot.source),
        ]),
        if (stale) ...[
          const SizedBox(height: 8),
          Text('This price is stale - pull to refresh.',
              style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        Text(
            'International spot price converted to INR - not Indian retail rates '
            '(excludes duties, GST, premiums). The high shown is the highest price '
            'observed by this app since the date above, not a market historical '
            'high, so buy/wait signals are paused.',
            style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String k, v;
  const _Fact(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Chip(
        label: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$k: ',
              style: GoogleFonts.poppins(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          TextSpan(
              text: v,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ])),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        side: const BorderSide(color: Colors.white24));
  }
}
