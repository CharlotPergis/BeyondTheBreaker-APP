import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();
  
  final _supabase = Supabase.instance.client;
  
  // Get real-time stream of readings
  Stream<List<Map<String, dynamic>>> getRealtimeReadings() {
    return _supabase
        .from('breaker_readings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(20);
  }
  
  // Get latest reading
  Future<Map<String, dynamic>?> getLatestReading() async {
    try {
      final response = await _supabase
          .from('breaker_readings')
          .select()
          .order('created_at', ascending: false)
          .limit(1);
          
      if (response.isNotEmpty) {
        return response[0];
      }
      return null;
    } catch (e) {
      print('Error getting latest reading: $e');
      return null;
    }
  }
  
  // Get history data
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50}) async {
    try {
      final response = await _supabase
          .from('breaker_readings')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
          
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting history: $e');
      return [];
    }
  }
}