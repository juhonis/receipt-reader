import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

abstract interface class ProductComparisonService {
  Future<ProductComparisonResult> productComparison(
    DurableId productId, {
    PurchaseDateRange? range,
  });
}
