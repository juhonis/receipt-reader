/// Storage-facing values; no database, image retention, or network transport.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:receipt_parser/receipt_parser.dart';

part 'src/values.dart';
part 'src/snapshot.dart';
part 'src/codec.dart';
part 'src/manual_review.dart';

part 'src/ocr_review.dart';

part 'src/deletion.dart';
part 'src/catalog.dart';
part 'src/purchase.dart';
part 'src/purchase_summary.dart';
part 'src/spending.dart';
part 'src/spending_dashboard.dart';
part 'src/category_spending.dart';

part 'src/product_link_review.dart';

part 'src/product_spending.dart';
