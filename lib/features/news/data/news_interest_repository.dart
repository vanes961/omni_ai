import 'package:omni_ai/features/news/models/news_interest_profile.dart';

abstract interface class NewsInterestRepository {
  Future<NewsInterestProfile> load();
  Future<void> save(NewsInterestProfile profile);
  Future<void> dispose();
}
