import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Beyond The Breaker',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0EA5E9),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: const Dashboard(),
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
  
  List<HistoryEntry> historyLog = [];
  List<FlSpot> tempSpots = [];
  List<FlSpot> currentSpots = [];
  List<FlSpot> hotspotSpots = [];
  List<FlSpot> overloadSpots = [];
  List<FlSpot> riskSpots = [];
  int dataPointIndex = 0;
  String _selectedMetric = 'All';
  
  RealtimeChannel? _channel;
  bool isConnected = false;
  bool isRealtimeWorking = false;
  Timer? _fallbackTimer;
  final RefreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  final List<String> metrics = ['All', 'Temperature', 'Current', 'Hotspot', 'Overload', 'Risk'];

  @override
  void initState() {
    super.initState();
    _connectToSupabase();
  }

  Future<void> _connectToSupabase() async {
    try {
      await _fetchHistoricalData();
      await _startRealtimeSubscription();
      
      Future.delayed(const Duration(seconds: 5), () {
        if (!isRealtimeWorking && mounted) {
          print('⚠️ Realtime not working, starting fallback polling');
          _startFallbackPolling();
        }
      });
      
      setState(() => isConnected = true);
      print('✅ Connected to Supabase');
    } catch (e) {
      print('❌ Connection error: $e');
      setState(() => isConnected = false);
      _startFallbackPolling();
    }
  }

  Future<void> _startRealtimeSubscription() async {
    final supabase = Supabase.instance.client;
    
    _channel = supabase
        .channel('breaker_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'breaker_readings',
          callback: (payload) {
            isRealtimeWorking = true;
            _onNewData(payload.newRecord);
          },
        )
        .subscribe((status, error) {
          if (error == null && mounted) {
            print('✅ Realtime connected');
            isRealtimeWorking = true;
          } else if (error != null) {
            print('❌ Realtime error: $error');
            isRealtimeWorking = false;
          }
        });
  }

  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) return;
      
      try {
        final response = await Supabase.instance.client
            .from('breaker_readings')
            .select()
            .order('created_at', ascending: false)
            .limit(1);
        
        if (response.isNotEmpty && mounted) {
          _onNewData(response.first);
        }
      } catch (e) {
        _generateDemoData();
      }
    });
  }

  void _onNewData(Map<String, dynamic> data) {
    try {
      final newTemp = (data['temperature_c'] ?? 0).toDouble();
      final newCurrent = (data['current_a'] ?? 0).toDouble();
      
      String newStatus = (data['breaker_state'] ?? 'Normal').toString();
      if (newStatus.toLowerCase() == 'normal') newStatus = 'Normal';
      else if (newStatus.toLowerCase() == 'overload') newStatus = 'Overload';
      else if (newStatus.toLowerCase() == 'warning') newStatus = 'Warning';
      else if (newStatus.toLowerCase() == 'overheating') newStatus = 'Overheating';
      
      final newHotspot = (data['hotspot_probability'] ?? 0).toDouble();
      final newOverload = (data['overload_probability'] ?? 0).toDouble();
      final newRisk = (data['composite_risk'] ?? 0).toDouble();
      
      if (!mounted) return;
      
      setState(() {
        temperature = newTemp;
        current = newCurrent;
        status = newStatus;
        hotspotProb = newHotspot;
        overloadProb = newOverload;
        compositeRisk = newRisk;
        
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
        if (historyLog.length > 100) historyLog.removeLast();
        
        dataPointIndex++;
        
        double scaledTemp = (temperature / 100).clamp(0, 1);
        double scaledCurrent = (current / 100).clamp(0, 1);
        
        tempSpots.add(FlSpot(dataPointIndex.toDouble(), scaledTemp));
        currentSpots.add(FlSpot(dataPointIndex.toDouble(), scaledCurrent));
        hotspotSpots.add(FlSpot(dataPointIndex.toDouble(), hotspotProb));
        overloadSpots.add(FlSpot(dataPointIndex.toDouble(), overloadProb));
        riskSpots.add(FlSpot(dataPointIndex.toDouble(), compositeRisk));
        
        if (tempSpots.length > 50) {
          tempSpots.removeAt(0);
          currentSpots.removeAt(0);
          hotspotSpots.removeAt(0);
          overloadSpots.removeAt(0);
          riskSpots.removeAt(0);
        }
      });
    } catch (e) {
      print('Error processing data: $e');
    }
  }

  void _generateDemoData() {
    if (!mounted) return;
    
    final rand = DateTime.now().millisecondsSinceEpoch % 100;
    setState(() {
      temperature = 25 + (rand % 50).toDouble();
      current = 15 + (rand % 40).toDouble();
      
      if (temperature > 75 || current > 45) {
        status = "Overheating";
        hotspotProb = 0.85;
        overloadProb = 0.75;
        compositeRisk = 0.80;
      } else if (temperature > 60 || current > 35) {
        status = "Overload";
        hotspotProb = 0.65;
        overloadProb = 0.70;
        compositeRisk = 0.675;
      } else if (temperature > 50 || current > 28) {
        status = "Warning";
        hotspotProb = 0.45;
        overloadProb = 0.50;
        compositeRisk = 0.475;
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
      if (historyLog.length > 100) historyLog.removeLast();
      
      dataPointIndex++;
      
      double scaledTemp = (temperature / 100).clamp(0, 1);
      double scaledCurrent = (current / 100).clamp(0, 1);
      
      tempSpots.add(FlSpot(dataPointIndex.toDouble(), scaledTemp));
      currentSpots.add(FlSpot(dataPointIndex.toDouble(), scaledCurrent));
      hotspotSpots.add(FlSpot(dataPointIndex.toDouble(), hotspotProb));
      overloadSpots.add(FlSpot(dataPointIndex.toDouble(), overloadProb));
      riskSpots.add(FlSpot(dataPointIndex.toDouble(), compositeRisk));
      
      if (tempSpots.length > 50) {
        tempSpots.removeAt(0);
        currentSpots.removeAt(0);
        hotspotSpots.removeAt(0);
        overloadSpots.removeAt(0);
        riskSpots.removeAt(0);
      }
    });
  }

  Future<void> _fetchHistoricalData() async {
    try {
      final response = await Supabase.instance.client
          .from('breaker_readings')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      
      if (response.isNotEmpty && mounted) {
        final entries = <HistoryEntry>[];
        
        for (var i = response.length - 1; i >= 0; i--) {
          final item = response[i];
          entries.add(HistoryEntry(
            timestamp: DateTime.parse(item['created_at']),
            temperature: (item['temperature_c'] ?? 0).toDouble(),
            current: (item['current_a'] ?? 0).toDouble(),
            status: (item['breaker_state'] ?? 'Normal').toString(),
            hotspotProb: (item['hotspot_probability'] ?? 0).toDouble(),
            overloadProb: (item['overload_probability'] ?? 0).toDouble(),
            compositeRisk: (item['composite_risk'] ?? 0).toDouble(),
          ));
        }
        
        setState(() {
          historyLog = entries.reversed.toList();
          
          tempSpots.clear();
          currentSpots.clear();
          hotspotSpots.clear();
          overloadSpots.clear();
          riskSpots.clear();
          
          for (int i = 0; i < historyLog.length; i++) {
            double scaledTemp = (historyLog[i].temperature / 100).clamp(0, 1);
            double scaledCurrent = (historyLog[i].current / 100).clamp(0, 1);
            
            tempSpots.add(FlSpot(i.toDouble(), scaledTemp));
            currentSpots.add(FlSpot(i.toDouble(), scaledCurrent));
            hotspotSpots.add(FlSpot(i.toDouble(), historyLog[i].hotspotProb));
            overloadSpots.add(FlSpot(i.toDouble(), historyLog[i].overloadProb));
            riskSpots.add(FlSpot(i.toDouble(), historyLog[i].compositeRisk));
          }
          dataPointIndex = historyLog.length;
          
          if (response.isNotEmpty) {
            final latest = response[0];
            temperature = (latest['temperature_c'] ?? 0).toDouble();
            current = (latest['current_a'] ?? 0).toDouble();
            status = (latest['breaker_state'] ?? 'Normal').toString();
            hotspotProb = (latest['hotspot_probability'] ?? 0).toDouble();
            overloadProb = (latest['overload_probability'] ?? 0).toDouble();
            compositeRisk = (latest['composite_risk'] ?? 0).toDouble();
          }
        });
      }
    } catch (e) {
      print('Error fetching history: $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (historyLog.isEmpty && mounted) _generateDemoData();
      });
    }
  }

  Future<void> _refreshData() async {
    await _fetchHistoricalData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Color getStatusColor() {
    if (status == "Normal") return const Color(0xFF22C55E);
    if (status == "Overload" || status == "Warning") return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  IconData getStatusIcon() {
    if (status == "Normal") return Icons.check_circle;
    if (status == "Overload" || status == "Warning") return Icons.warning_amber;
    return Icons.whatshot;
  }

  String getRiskLevel() {
    if (compositeRisk > 0.7) return "CRITICAL";
    if (compositeRisk > 0.4) return "ELEVATED";
    return "SAFE";
  }

  double getRiskPercentage() => compositeRisk * 100;

  String getMitigationSuggestion() {
    if (status == "Overheating") return "⚠️ Isolate circuit immediately!";
    if (status == "Overload") return "⚠️ Reduce load by 15-20% immediately!";
    if (status == "Warning") return "⚠️ Reduce load by 15-20%";
    return "✅ System operating normally";
  }

  List<LineChartBarData> _getChartLines() {
    List<LineChartBarData> lines = [];
    
    if (_selectedMetric == 'All' || _selectedMetric == 'Temperature') {
      lines.add(LineChartBarData(
        spots: tempSpots,
        isCurved: true,
        color: const Color(0xFF3B82F6),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    
    if (_selectedMetric == 'All' || _selectedMetric == 'Current') {
      lines.add(LineChartBarData(
        spots: currentSpots,
        isCurved: true,
        color: const Color(0xFF06B6D4),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    
    if (_selectedMetric == 'All' || _selectedMetric == 'Hotspot') {
      lines.add(LineChartBarData(
        spots: hotspotSpots,
        isCurved: true,
        color: const Color(0xFF8B5CF6),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    
    if (_selectedMetric == 'All' || _selectedMetric == 'Overload') {
      lines.add(LineChartBarData(
        spots: overloadSpots,
        isCurved: true,
        color: const Color(0xFFF59E0B),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    
    if (_selectedMetric == 'All' || _selectedMetric == 'Risk') {
      lines.add(LineChartBarData(
        spots: riskSpots,
        isCurved: true,
        color: const Color(0xFFEF4444),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 16),
            child: isMobile 
                ? _buildMobileLayout(screenHeight)
                : _buildDesktopLayout(screenHeight),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(double screenHeight) {
    return Column(
      children: [
        _buildHeader(true),
        SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildStatusCard(),
                SizedBox(height: 8),
                _buildSensorRow(true),
                SizedBox(height: 8),
                _buildRiskMeter(),
                SizedBox(height: 8),
                _buildPredictions(true),
                SizedBox(height: 8),
                _buildMitigation(),
                SizedBox(height: 8),
                Container(
                  height: screenHeight * 0.35,
                  child: _buildCombinedChart(true),
                ),
                SizedBox(height: 8),
                Container(
                  height: screenHeight * 0.4,
                  child: _buildRecentEvents(true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(double screenHeight) {
    return Column(
      children: [
        _buildHeader(false),
        SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _buildStatusCard(),
                    SizedBox(height: 10),
                    _buildSensorRow(false),
                    SizedBox(height: 10),
                    Expanded(
                      child: _buildCombinedChart(false),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _buildRiskMeter(),
                    SizedBox(height: 10),
                    _buildPredictions(false),
                    SizedBox(height: 10),
                    _buildMitigation(),
                    SizedBox(height: 10),
                    Expanded(
                      child: _buildRecentEvents(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA5E9).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: isMobile 
          ? Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.electrical_services,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Beyond The Breaker",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                isConnected ? "LIVE" : "DEMO",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.refresh, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        DateFormat('HH:mm:ss').format(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.electrical_services,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Beyond The Breaker",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isConnected ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            isConnected ? "LIVE DATA STREAM" : "DEMO MODE",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.refresh, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        DateFormat('HH:mm:ss').format(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [getStatusColor().withOpacity(0.2), getStatusColor().withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: getStatusColor().withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CURRENT STATUS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: getStatusColor(),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: getStatusColor().withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    getRiskLevel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: getStatusColor(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: getStatusColor().withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              getStatusIcon(),
              size: 36,
              color: getStatusColor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorRow(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildSensorCard(
            "TEMP",
            temperature.toStringAsFixed(1),
            "°C",
            Icons.thermostat,
            const Color(0xFF3B82F6),
            temperature,
            100,
          ),
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: _buildSensorCard(
            "CURRENT",
            current.toStringAsFixed(1),
            "A",
            Icons.electric_bolt,
            const Color(0xFF06B6D4),
            current,
            100,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorCard(String title, String value, String unit, IconData icon, Color color, double currentValue, double maxValue) {
    double progress = (currentValue / maxValue).clamp(0, 1);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
            ],
          ),
          SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedChart(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline, size: 14, color: Colors.white.withOpacity(0.7)),
                  SizedBox(width: 4),
                  Text(
                    "METRICS TREND",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMetric,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.7), size: 16),
                    items: metrics.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedMetric = newValue!;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Expanded(
            child: tempSpots.isEmpty
                ? Center(child: Text("Waiting for data...", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.1),
                            strokeWidth: 1,
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.white.withOpacity(0.1),
                            strokeWidth: 1,
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() % 5 == 0 && value >= 0 && value < dataPointIndex) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                                  ),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                "${(value * 100).toInt()}%",
                                style: const TextStyle(fontSize: 9, color: Colors.white54),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      minX: 0,
                      maxX: dataPointIndex > 0 ? dataPointIndex.toDouble() : 10,
                      minY: 0,
                      maxY: 1,
                      lineBarsData: _getChartLines(),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              String label = '';
                              if (spot.barIndex == 0) label = 'Temp: ${(spot.y * 100).toInt()}°C';
                              else if (spot.barIndex == 1) label = 'Current: ${(spot.y * 100).toInt()}A';
                              else if (spot.barIndex == 2) label = 'Hotspot: ${(spot.y * 100).toInt()}%';
                              else if (spot.barIndex == 3) label = 'Overload: ${(spot.y * 100).toInt()}%';
                              else if (spot.barIndex == 4) label = 'Risk: ${(spot.y * 100).toInt()}%';
                              
                              return LineTooltipItem(
                                label,
                                const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              );
                            }).toList();
                          },
                          tooltipBgColor: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _buildLegend("Temp", const Color(0xFF3B82F6)),
              _buildLegend("Current", const Color(0xFF06B6D4)),
              _buildLegend("Hotspot", const Color(0xFF8B5CF6)),
              _buildLegend("Overload", const Color(0xFFF59E0B)),
              _buildLegend("Risk", const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildRiskMeter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "RISK INDEX",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${getRiskPercentage().toInt()}%",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: getStatusColor(),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      getRiskLevel(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: getStatusColor(),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: getRiskPercentage() / 100,
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation(getStatusColor()),
                    ),
                    Text(
                      "${getRiskPercentage().toInt()}%",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEF4444)],
                stops: [0, 0.5, 1],
              ),
            ),
            child: LinearProgressIndicator(
              value: getRiskPercentage() / 100,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictions(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildPredictionCard(
            "HOTSPOT",
            hotspotProb,
            const Color(0xFF8B5CF6),
            Icons.local_fire_department,
          ),
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: _buildPredictionCard(
            "OVERLOAD",
            overloadProb,
            const Color(0xFFF59E0B),
            Icons.electric_bolt,
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionCard(String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            "${(value * 100).toInt()}%",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 6),
          LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildMitigation() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0EA5E9).withOpacity(0.15), const Color(0xFF7C3AED).withOpacity(0.15)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF7C3AED)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              getMitigationSuggestion(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEvents(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, size: 14, color: Colors.white.withOpacity(0.7)),
                    SizedBox(width: 6),
                    Text(
                      "RECENT EVENTS",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (historyLog.isNotEmpty)
                      GestureDetector(
                        onTap: _viewFullHistory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0EA5E9).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.list_alt, size: 10, color: Color(0xFF0EA5E9)),
                              SizedBox(width: 3),
                              Text("All", style: TextStyle(fontSize: 9, color: Color(0xFF0EA5E9), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(width: 6),
                    if (historyLog.isNotEmpty)
                      GestureDetector(
                        onTap: _clearHistory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline, size: 10, color: Color(0xFFEF4444)),
                              SizedBox(width: 3),
                              Text("Clear", style: TextStyle(fontSize: 9, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: historyLog.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 40, color: Colors.white.withOpacity(0.1)),
                        SizedBox(height: 8),
                        Text(
                          "No history",
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: historyLog.length > 8 ? 8 : historyLog.length,
                    itemBuilder: (context, index) {
                      final entry = historyLog[index];
                      final statusColor = entry.status == "Normal" 
                          ? const Color(0xFF22C55E) 
                          : (entry.status == "Overload" || entry.status == "Warning" 
                              ? const Color(0xFFF59E0B) 
                              : const Color(0xFFEF4444));
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                entry.status == "Normal" 
                                    ? Icons.check_circle 
                                    : (entry.status == "Overload" || entry.status == "Warning" 
                                        ? Icons.warning_amber 
                                        : Icons.whatshot),
                                color: statusColor,
                                size: 14,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "${entry.temperature.toStringAsFixed(1)}°C • ${entry.current.toStringAsFixed(1)}A",
                                    style: const TextStyle(fontSize: 8, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              DateFormat('HH:mm').format(entry.timestamp),
                              style: const TextStyle(fontSize: 9, color: Color(0xFF0EA5E9), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _viewFullHistory() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, size: 20, color: const Color(0xFF0EA5E9)),
                      SizedBox(width: 10),
                      Text(
                        "FULL HISTORY (${historyLog.length})",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: historyLog.length,
                itemBuilder: (context, index) {
                  final entry = historyLog[index];
                  final statusColor = entry.status == "Normal" 
                      ? const Color(0xFF22C55E) 
                      : (entry.status == "Overload" || entry.status == "Warning" 
                          ? const Color(0xFFF59E0B) 
                          : const Color(0xFFEF4444));
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    entry.status == "Normal" 
                                        ? Icons.check_circle 
                                        : (entry.status == "Overload" || entry.status == "Warning" 
                                            ? Icons.warning_amber 
                                            : Icons.whatshot),
                                    color: statusColor,
                                    size: 20,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      DateFormat('MMM dd, yyyy').format(entry.timestamp),
                                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              DateFormat('HH:mm:ss').format(entry.timestamp),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF0EA5E9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildDetailChip("Temp", "${entry.temperature.toStringAsFixed(1)}°C", const Color(0xFF3B82F6)),
                            _buildDetailChip("Current", "${entry.current.toStringAsFixed(1)}A", const Color(0xFF06B6D4)),
                            _buildDetailChip("Hotspot", "${(entry.hotspotProb * 100).toInt()}%", const Color(0xFF8B5CF6)),
                            _buildDetailChip("Overload", "${(entry.overloadProb * 100).toInt()}%", const Color(0xFFF59E0B)),
                            _buildDetailChip("Risk", "${(entry.compositeRisk * 100).toInt()}%", const Color(0xFFEF4444)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Clear History", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text("Clear all history logs?", style: TextStyle(color: Colors.white, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                historyLog.clear();
                tempSpots.clear();
                currentSpots.clear();
                hotspotSpots.clear();
                overloadSpots.clear();
                riskSpots.clear();
                dataPointIndex = 0;
              });
              Navigator.pop(context);
            },
            child: const Text("Clear", style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}