import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

/// Match complete candidate names using the existing conservative name key.
/// Different identities with the same name remain separate, ambiguous matches.
List<ReceiptBranch> recommendedBranches(
  Iterable<ReceiptBranchCandidate> candidates,
  Iterable<ReceiptBranch> branches,
) {
  final names = candidates.map((c) => normalizeReceiptNameV1(c.name)).toSet();
  return List.unmodifiable(
    branches.where((b) => names.contains(normalizeReceiptNameV1(b.name))),
  );
}
