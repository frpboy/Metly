import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/price_model.dart';
import '../utils/formatters.dart';

class SignalCard extends StatelessWidget {
  final PriceSnapshot snapshot;
  final SignalResult result;
  const SignalCard({super.key, required this.snapshot, required this.result});
  @override
  Widget build(BuildContext context) {
    final isBuy = result.signal == Signal.buy;
    final bg = isBuy ? const Color(0xFF073B2A) : const Color(0xFF3B0707);
    final border = isBuy ? const Color(0xFF17A36B) : const Color(0xFFB34A4A);
    final title =
        '${isBuy ? "BUY" : "WAIT"} ${snapshot.metal.label.toUpperCase()} ${isBuy ? "NOW!" : ""}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withOpacity(0.6), width: 1.4)),
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
        ]),
        const SizedBox(height: 10),
        Text(result.reason,
            style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.9),
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
        backgroundColor: Colors.white.withOpacity(0.06),
        side: const BorderSide(color: Colors.white24));
  }
}
