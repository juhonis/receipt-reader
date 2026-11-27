import 'package:integration_test/integration_test.dart';

import '../test/branch_recommendations_test.dart'
    show runBranchRecommendationTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runBranchRecommendationTests();
}
