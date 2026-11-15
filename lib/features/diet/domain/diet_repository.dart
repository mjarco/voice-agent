import 'package:voice_agent/features/diet/domain/diet_models.dart';

/// The diet's reads and writes, the same routes the web UI uses.
abstract class DietRepository {
  Future<DietDay> day(String day);

  /// A meal corrected: only what is given changes.
  Future<void> editMeal(String id, {int? kcal, int? low, int? high, double? proteinG, String? day, String? time});

  Future<void> removeMeal(String id);

  /// A planned meal logged as eaten, from the menu, now.
  Future<void> eatPlanned(String menuEntryId);

  Future<List<DietMenuEntry>> menu(String from, String to);

  Future<void> planOwnMeal({required String day, required String slot, required String ownMealId});

  Future<void> unplan(String id);

  Future<List<DietOwnMeal>> ownMeals();

  Future<void> removeOwnMeal(String id);

  Future<List<DietTarget>> targets();

  Future<void> setTarget({required int kcalMin, required int kcalMax, int? proteinMin, int? reserveKcal, String? from});
}
