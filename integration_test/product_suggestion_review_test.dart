import 'package:integration_test/integration_test.dart';

import '../test/product_suggestion_review_test.dart'
    show runProductSuggestionReviewTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runProductSuggestionReviewTests();
}
