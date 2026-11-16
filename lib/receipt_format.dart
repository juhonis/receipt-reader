import 'package:receipt_domain/receipt_domain.dart';

String receiptDateText(StoredReceiptDate date) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${date.day}.${date.month}.${date.year}';
  return date.hour == null
      ? day
      : '$day ${two(date.hour!)}:${two(date.minute!)}'
            '${date.second == null ? '' : ':${two(date.second!)}'}';
}
