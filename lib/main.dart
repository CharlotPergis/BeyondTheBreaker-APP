import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qkniqwgcwvxkgjciccad.supabase.co',
    anonKey: 'sb_publishable_pzHW1LlymSCVL876qchBKw_pPY0xN-2',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Breaker Monitor Pro',
      home: Dashboard(),
    );
  }
}

class HistoryEntry {
  final DateTime timestamp;
  final double temperature;
  final double current;
  final String status;
  final double hotspotProb;
  final double overloadProb;
  final double compositeRisk;

  HistoryEntry({
    required this.timestamp,
    required this.temperature,
    required this.current,
    required this.status,
    this.hotspotProb = 0,
    this.overloadProb = 0,
    this.compositeRisk = 0,
  });
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double temperature = 0;
  double current = 0;
  String status = "Normal";
  double hotspotProb = 0;
  double overloadProb = 0;
  double compositeRisk = 0;
  
  // History and trend data
  List<HistoryEntry> historyLog = [];
  List<FlSpot> tempSpots = [];
  List<FlSpot> currentSpots = [];
  int dataPointIndex = 0;
  int _selectedTab = 0; // 0 = Dashboard, 1 = History
  
  late RealtimeChannel _channel;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToSupabase();
  }

  Future<void> _connectToSupabase() async {
    try {
      await _fetchHistoricalData();
      _subscribeToRealtime();
      setState(() => isConnected = true);
      print('✅ Connected to Supabase cloud');
    } catch (e) {
      print('❌ Supabase connection error: $e');
      setState(() => isConnected = false);
      _startLocalSimulation();
    }
  }
  
  void _subscribeToRealtime() {
    _channel = Supabase.instance.client
        .channel('breaker_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'breaker_readings',
          callback: (payload) {
            _onNewData(payload.newRecord);
          },
        )
        .subscribe();
  }
  
  void _onNewData(Map<String, dynamic> data) {
    final newTemp = (data['temperature_c'] ?? 0).toDouble();
    final newCurrent = (data['current_a'] ?? 0).toDouble();
    final newStatus = data['breaker_state'] ?? 'Normal';
    final newHotspot = (data['hotspot_probability'] ?? 0).toDouble();
    final newOverload = (data['overload_probability'] ?? 0).toDouble();
    final newRisk = (data['composite_risk'] ?? 0).toDouble();
    
    setState(() {
      temperature = newTemp;
      current = newCurrent;
      status = newStatus;
      hotspotProb = newHotspot;
      overloadProb = newOverload;
      compositeRisk = newRisk;
      
      // Add to history
      final newEntry = HistoryEntry(
        timestamp: DateTime.now(),
        temperature: temperature,
        current: current,
        status: status,
        hotspotProb: hotspotProb,
        overloadProb: overloadProb,
        compositeRisk: compositeRisk,
      );
      historyLog.insert(0, newEntry);
      if (historyLog.length > 50) historyLog.removeLast();
      
      // Update graphs
      dataPointIndex++;
      tempSpots.add(FlSpot(dataPointIndex.toDouble(), temperature));
      currentSpots.add(FlSpot(dataPointIndex.toDouble(), current));
      if (tempSpots.length > 20) {
        tempSpots.removeAt(0);
        currentSpots.removeAt(0);
      }
    });
  }
  
  Future<void> _fetchHistoricalData() async {
    try {
      final response = await Supabase.instance.client
          .from('breaker_readings')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      
      if (response.isNotEmpty) {
        final List<HistoryEntry> historicalEntries = [];
        final List<double> historicalTemps = [];
        final List<double> historicalCurrents = [];
        
        for (var i = response.length - 1; i >= 0; i--) {
          final item = response[i];
          final entry = HistoryEntry(
            timestamp: DateTime.parse(item['created_at']),
            temperature: (item['temperature_c'] ?? 0).toDouble(),
            current: (item['current_a'] ?? 0).toDouble(),
            status: item['breaker_state'] ?? 'Normal',
            hotspotProb: (item['hotspot_probability'] ?? 0).toDouble(),
            overloadProb: (item['overload_probability'] ?? 0).toDouble(),
            compositeRisk: (item['composite_risk'] ?? 0).toDouble(),
          );
          historicalEntries.add(entry);
          historicalTemps.add(entry.temperature);
          historicalCurrents.add(entry.current);
        }
        
        setState(() {
          historyLog = historicalEntries.reversed.toList();
          
          tempSpots = [];
          currentSpots = [];
          for (int i = 0; i < historicalTemps.length; i++) {
            tempSpots.add(FlSpot(i.toDouble(), historicalTemps[i]));
            currentSpots.add(FlSpot(i.toDouble(), historicalCurrents[i]));
          }
          dataPointIndex = historicalTemps.length;
          
          if (response.isNotEmpty) {
            final latest = response[0];
            temperature = (latest['temperature_c'] ?? 0).toDouble();
            current = (latest['current_a'] ?? 0).toDouble();
            status = latest['breaker_state'] ?? 'Normal';
            hotspotProb = (latest['hotspot_probability'] ?? 0).toDouble();
            overloadProb = (latest['overload_probability'] ?? 0).toDouble();
            compositeRisk = (latest['composite_risk'] ?? 0).toDouble();
          }
        });
        print('✅ Loaded ${historyLog.length} historical records');
      }
    } catch (e) {
      print('Error fetching history: $e');
    }
  }
  
  void _startLocalSimulation() {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      final seconds = DateTime.now().second;
      setState(() {
        temperature = 55 + (seconds % 40);
        current = 10 + (seconds % 25);
        
        if (temperature > 80 || current > 28) {
          status = "Overheating";
          hotspotProb = 0.85;
          overloadProb = 0.75;
          compositeRisk = 0.80;
        } else if (temperature > 65 || current > 22) {
          status = "Warning";
          hotspotProb = 0.45;
          overloadProb = 0.55;
          compositeRisk = 0.50;
        } else {
          status = "Normal";
          hotspotProb = 0.15;
          overloadProb = 0.20;
          compositeRisk = 0.175;
        }
        
        final newEntry = HistoryEntry(
          timestamp: DateTime.now(),
          temperature: temperature,
          current: current,
          status: status,
          hotspotProb: hotspotProb,
          overloadProb: overloadProb,
          compositeRisk: compositeRisk,
        );
        historyLog.insert(0, newEntry);
        if (historyLog.length > 50) historyLog.removeLast();
        
        dataPointIndex++;
        tempSpots.add(FlSpot(dataPointIndex.toDouble(), temperature));
        currentSpots.add(FlSpot(dataPointIndex.toDouble(), current));
        if (tempSpots.length > 20) {
          tempSpots.removeAt(0);
          currentSpots.removeAt(0);
        }
      });
    });
  }

  @override
  void dispose() {
    _channel.unsubscribe();
    super.dispose();
  }

  Color getStatusColor() {
    if (status == "Normal") return const Color(0xFF22C55E);
    if (status == "Warning") return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  IconData getStatusIcon() {
    if (status == "Normal") return Icons.check_circle;
    if (status == "Warning") return Icons.warning_amber;
    return Icons.fireplace;
  }

  String getRiskLevel() {
    if (compositeRisk > 0.7) return "CRITICAL";
    if (compositeRisk > 0.4) return "ELEVATED";
    return "SAFE";
  }

  double getRiskPercentage() => compositeRisk * 100;

  String getMitigationSuggestion() {
    if (status == "Overheating") {
      return "Isolate circuit immediately!";
    } else if (status == "Warning") {
      return "Reduce load by 15-20%";
    } else {
      return "System operating normally";
    }
  }

  void clearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to clear all history logs?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                historyLog.clear();
                tempSpots.clear();
                currentSpots.clear();
                dataPointIndex = 0;
              });
              Navigator.pop(context);
            },
            child: const Text("Clear", style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  String formatFullTimestamp(DateTime timestamp) {
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  String formatFullDate(DateTime timestamp) {
    return DateFormat('MM/dd/yyyy').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF0F172A), const Color(0xFF1E1B4B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with Tabs
              Container(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0EA5E9), Color(0xFF7C3AED)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.electrical_services, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Breaker Monitor Pro",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isConnected ? "Cloud Connected" : "Local Mode",
                              style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Tab buttons
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          _buildTabButton(0, "Dashboard", Icons.dashboard),
                          _buildTabButton(1, "History", Icons.history),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Main Content - Tab based
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
                  children: [
                    // Dashboard Tab
                    SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: 8),
                      child: Column(
                        children: [
                          // Status Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  getStatusColor().withOpacity(0.2),
                                  getStatusColor().withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: getStatusColor().withOpacity(0.3), width: 1),
                            ),
                            child: Column(
                              children: [
                                Icon(getStatusIcon(), size: 32, color: getStatusColor()),
                                const SizedBox(height: 4),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: getStatusColor()),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  getRiskLevel(),
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Sensor Cards - Blue for Temp, Yellow for Current
                          Row(
                            children: [
                              Expanded(
                                child: _buildSensorCard(
                                  title: "Temperature",
                                  value: temperature.toStringAsFixed(1),
                                  unit: "°C",
                                  icon: Icons.thermostat,
                                  color: const Color(0xFF3B82F6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSensorCard(
                                  title: "Current",
                                  value: current.toStringAsFixed(1),
                                  unit: "A",
                                  icon: Icons.electric_bolt,
                                  color: const Color(0xFFEAB308),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Temperature Trend Graph
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.show_chart, size: 14, color: const Color(0xFF3B82F6)),
                                    const SizedBox(width: 6),
                                    const Text("TEMP TREND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80,
                                  child: tempSpots.isEmpty
                                      ? const Center(child: Text("Collecting...", style: TextStyle(fontSize: 10, color: Color(0xFF64748B))))
                                      : LineChart(
                                          LineChartData(
                                            gridData: const FlGridData(show: false),
                                            titlesData: const FlTitlesData(show: false),
                                            borderData: FlBorderData(show: false),
                                            lineBarsData: [
                                              LineChartBarData(
                                                spots: tempSpots,
                                                isCurved: true,
                                                color: const Color(0xFF3B82F6),
                                                barWidth: 2,
                                                dotData: const FlDotData(show: false),
                                                belowBarData: BarAreaData(show: true, color: const Color(0xFF3B82F6).withOpacity(0.1)),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Current Trend Graph
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.show_chart, size: 14, color: const Color(0xFFEAB308)),
                                    const SizedBox(width: 6),
                                    const Text("CURRENT TREND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80,
                                  child: currentSpots.isEmpty
                                      ? const Center(child: Text("Collecting...", style: TextStyle(fontSize: 10, color: Color(0xFF64748B))))
                                      : LineChart(
                                          LineChartData(
                                            gridData: const FlGridData(show: false),
                                            titlesData: const FlTitlesData(show: false),
                                            borderData: FlBorderData(show: false),
                                            lineBarsData: [
                                              LineChartBarData(
                                                spots: currentSpots,
                                                isCurved: true,
                                                color: const Color(0xFFEAB308),
                                                barWidth: 2,
                                                dotData: const FlDotData(show: false),
                                                belowBarData: BarAreaData(show: true, color: const Color(0xFFEAB308).withOpacity(0.1)),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Risk Meter
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("RISK METER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "${getRiskPercentage().toInt()}%",
                                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                          Text(
                                            getRiskLevel(),
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: getStatusColor()),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 45,
                                      height: 45,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            value: getRiskPercentage() / 100,
                                            strokeWidth: 4,
                                            backgroundColor: const Color(0xFF334155),
                                            valueColor: AlwaysStoppedAnimation<Color>(getStatusColor()),
                                          ),
                                          Text(
                                            "${getRiskPercentage().toInt()}%",
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: getRiskPercentage() / 100,
                                  backgroundColor: const Color(0xFF334155),
                                  valueColor: AlwaysStoppedAnimation<Color>(getStatusColor()),
                                  minHeight: 3,
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // ML Predictions
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF334155), width: 1),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("HOTSPOT", style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                                      Text("${(hotspotProb * 100).toInt()}%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                                      LinearProgressIndicator(
                                        value: hotspotProb,
                                        backgroundColor: const Color(0xFF334155),
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                                        minHeight: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF334155), width: 1),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("OVERLOAD", style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                                      Text("${(overloadProb * 100).toInt()}%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFEAB308))),
                                      LinearProgressIndicator(
                                        value: overloadProb,
                                        backgroundColor: const Color(0xFF334155),
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFFEAB308)),
                                        minHeight: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Mitigation
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF0EA5E9).withOpacity(0.1),
                                  const Color(0xFF7C3AED).withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0EA5E9).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.auto_awesome, color: Color(0xFF0EA5E9), size: 14),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    getMitigationSuggestion(),
                                    style: const TextStyle(fontSize: 11, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    
                    // History Tab
                    Column(
                      children: [
                        // History Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "📋 EVENT HISTORY",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                              ),
                              if (historyLog.isNotEmpty)
                                GestureDetector(
                                  onTap: clearHistory,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.delete_outline, size: 12, color: Color(0xFFEF4444)),
                                        SizedBox(width: 4),
                                        Text("Clear", style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        // History List
                        Expanded(
                          child: historyLog.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.history, size: 40, color: const Color(0xFF334155)),
                                      const SizedBox(height: 8),
                                      const Text("No history yet", style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: historyLog.length,
                                  itemBuilder: (context, index) {
                                    final entry = historyLog[index];
                                    final statusColor = entry.status == "Normal" 
                                        ? const Color(0xFF22C55E)
                                        : (entry.status == "Warning" ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                                    
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: statusColor.withOpacity(0.3), width: 0.5),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              entry.status == "Normal" ? Icons.check_circle : (entry.status == "Warning" ? Icons.warning_amber : Icons.fireplace),
                                              color: statusColor,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.status.toUpperCase(),
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Icon(Icons.thermostat, size: 10, color: const Color(0xFF3B82F6)),
                                                    const SizedBox(width: 2),
                                                    Text("${entry.temperature.toStringAsFixed(1)}°C", style: const TextStyle(fontSize: 10)),
                                                    const SizedBox(width: 8),
                                                    Icon(Icons.electric_bolt, size: 10, color: const Color(0xFFEAB308)),
                                                    const SizedBox(width: 2),
                                                    Text("${entry.current.toStringAsFixed(1)}A", style: const TextStyle(fontSize: 10)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            formatFullTimestamp(entry.timestamp),
                                            style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0EA5E9) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                ),
                TextSpan(
                  text: unit,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}