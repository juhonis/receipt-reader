import 'package:integration_test/integration_test.dart';

import '../test/sequential_problem_review_test.dart'
    show runSequentialProblemReviewTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runSequentialProblemReviewTests();
}
