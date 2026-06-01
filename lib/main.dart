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
      title: 'Beyond The Bre4ker',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF5E9BFF),
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
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
  final String recommendedAction;

  HistoryEntry({
    required this.timestamp,
    required this.temperature,
    required this.current,
    required this.status,
    this.hotspotProb = 0,
    this.overloadProb = 0,
    this.compositeRisk = 0,
    this.recommendedAction = '',
  });
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // Data
  double temperature = 0, current = 0, hotspotProb = 0, overloadProb = 0, compositeRisk = 0;
  String status = "Normal", recommendedAction = "System operating normally";
  List<HistoryEntry> historyLog = [];
  List<FlSpot> tempSpots = [], currentSpots = [], hotspotSpots = [], overloadSpots = [], riskSpots = [];
  int dataPointIndex = 0;
  String _selectedMetric = 'All';
  
  Timer? _pollingTimer;
  bool isConnected = false;
  final List<String> metrics = ['All', 'Temperature', 'Current', 'Hotspot', 'Overload', 'Risk'];

  @override
  void initState() {
    super.initState();
    _connectToSupabase();
  }

  Future<void> _connectToSupabase() async {
    try {
      await _fetchHistoricalData();
      _startPolling();
      setState(() => isConnected = true);
    } catch (e) {
      setState(() => isConnected = false);
      _startDemoData();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) return;
      try {
        final response = await Supabase.instance.client
            .from('breaker_readings')
            .select()
            .order('created_at', ascending: false)
            .limit(1);
        if (response.isNotEmpty && mounted) _onNewData(response.first);
      } catch (e) {}
    });
  }

  void _startDemoData() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) _generateDemoData();
    });
  }

  void _onNewData(Map<String, dynamic> data) {
    try {
      final newTemp = (data['temperature_c'] ?? 0).toDouble();
      final newCurrent = (data['current_a'] ?? 0).toDouble();
      String newStatus = _normalizeStatus(data['breaker_state'] ?? 'Normal');
      
      setState(() {
        temperature = newTemp;
        current = newCurrent;
        status = newStatus;
        hotspotProb = (data['hotspot_probability'] ?? 0).toDouble();
        overloadProb = (data['overload_probability'] ?? 0).toDouble();
        compositeRisk = (data['composite_risk'] ?? 0).toDouble();
        recommendedAction = (data['recommended_action'] ?? 'System operating normally').toString();
        
        _addHistoryEntry(HistoryEntry(
          timestamp: DateTime.now(),
          temperature: temperature,
          current: current,
          status: status,
          hotspotProb: hotspotProb,
          overloadProb: overloadProb,
          compositeRisk: compositeRisk,
          recommendedAction: recommendedAction,
        ));
      });
    } catch (e) {}
  }

  void _generateDemoData() {
    final rand = DateTime.now().millisecondsSinceEpoch % 100;
    setState(() {
      temperature = 25 + (rand % 50).toDouble();
      current = 15 + (rand % 40).toDouble();
      
      if (temperature > 75 || current > 45) {
        status = "Critical";
        hotspotProb = 0.85; overloadProb = 0.75; compositeRisk = 0.80;
        recommendedAction = "⚠️ CRITICAL: Isolate circuit immediately! Severe overheating detected.";
      } else if (temperature > 60 || current > 35) {
        status = "Overload";
        hotspotProb = 0.65; overloadProb = 0.70; compositeRisk = 0.675;
        recommendedAction = "⚠️ WARNING: Reduce load by 15-20% immediately!";
      } else if (temperature > 50 || current > 28) {
        status = "Warning";
        hotspotProb = 0.45; overloadProb = 0.50; compositeRisk = 0.475;
        recommendedAction = "⚠️ Monitor system: Elevated temperature/current detected.";
      } else {
        status = "Normal";
        hotspotProb = 0.15; overloadProb = 0.20; compositeRisk = 0.175;
        recommendedAction = "✅ System operating normally. All parameters within safe range.";
      }
      
      _addHistoryEntry(HistoryEntry(
        timestamp: DateTime.now(),
        temperature: temperature,
        current: current,
        status: status,
        hotspotProb: hotspotProb,
        overloadProb: overloadProb,
        compositeRisk: compositeRisk,
        recommendedAction: recommendedAction,
      ));
    });
  }

  void _addHistoryEntry(HistoryEntry entry) {
    historyLog.insert(0, entry);
    if (historyLog.length > 100) historyLog.removeLast();
    
    dataPointIndex++;
    tempSpots.add(FlSpot(dataPointIndex.toDouble(), (temperature / 100).clamp(0, 1)));
    currentSpots.add(FlSpot(dataPointIndex.toDouble(), (current / 100).clamp(0, 1)));
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
  }

  String _normalizeStatus(String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'normal') return 'Normal';
    if (lower == 'overload') return 'Overload';
    if (lower == 'warning') return 'Warning';
    if (lower == 'critical' || lower == 'overheating') return 'Critical';
    return 'Normal';
  }

  Future<void> _fetchHistoricalData() async {
    try {
      final response = await Supabase.instance.client
          .from('breaker_readings')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      
      if (response.isNotEmpty && mounted) {
        setState(() {
          historyLog.clear();
          tempSpots.clear();
          currentSpots.clear();
          hotspotSpots.clear();
          overloadSpots.clear();
          riskSpots.clear();
          
          for (int i = response.length - 1; i >= 0; i--) {
            final item = response[i];
            historyLog.add(HistoryEntry(
              timestamp: DateTime.parse(item['created_at']),
              temperature: (item['temperature_c'] ?? 0).toDouble(),
              current: (item['current_a'] ?? 0).toDouble(),
              status: _normalizeStatus(item['breaker_state'] ?? 'Normal'),
              hotspotProb: (item['hotspot_probability'] ?? 0).toDouble(),
              overloadProb: (item['overload_probability'] ?? 0).toDouble(),
              compositeRisk: (item['composite_risk'] ?? 0).toDouble(),
              recommendedAction: (item['recommended_action'] ?? 'System operating normally').toString(),
            ));
          }
          
          for (int i = 0; i < historyLog.length; i++) {
            tempSpots.add(FlSpot(i.toDouble(), (historyLog[i].temperature / 100).clamp(0, 1)));
            currentSpots.add(FlSpot(i.toDouble(), (historyLog[i].current / 100).clamp(0, 1)));
            hotspotSpots.add(FlSpot(i.toDouble(), historyLog[i].hotspotProb));
            overloadSpots.add(FlSpot(i.toDouble(), historyLog[i].overloadProb));
            riskSpots.add(FlSpot(i.toDouble(), historyLog[i].compositeRisk));
          }
          dataPointIndex = historyLog.length;
          
          if (response.isNotEmpty) {
            final latest = response[0];
            temperature = (latest['temperature_c'] ?? 0).toDouble();
            current = (latest['current_a'] ?? 0).toDouble();
            status = _normalizeStatus(latest['breaker_state'] ?? 'Normal');
            hotspotProb = (latest['hotspot_probability'] ?? 0).toDouble();
            overloadProb = (latest['overload_probability'] ?? 0).toDouble();
            compositeRisk = (latest['composite_risk'] ?? 0).toDouble();
            recommendedAction = (latest['recommended_action'] ?? 'System operating normally').toString();
          }
        });
      }
    } catch (e) {
      _startDemoData();
    }
  }

  Color getStatusColor() {
    if (status == "Normal") return const Color(0xFF4ADE80);
    if (status == "Warning") return const Color(0xFFFBBF24);
    if (status == "Overload") return const Color(0xFFFB923C);
    return const Color(0xFFF87171);
  }

  IconData getStatusIcon() {
    if (status == "Normal") return Icons.check_circle;
    if (status == "Warning") return Icons.warning_amber;
    if (status == "Overload") return Icons.electric_bolt;
    return Icons.whatshot;
  }

  String getRiskLevel() => compositeRisk > 0.7 ? "CRITICAL" : compositeRisk > 0.4 ? "ELEVATED" : "SAFE";
  double getRiskPercentage() => compositeRisk * 100;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0E27), Color(0xFF10152E)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 16),
            child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() => Column(
        children: [
          _buildHeader(true),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 8),
                  _buildSensorRow(true),
                  const SizedBox(height: 8),
                  _buildRiskMeter(),
                  const SizedBox(height: 8),
                  _buildPredictions(true),
                  const SizedBox(height: 8),
                  _buildMitigation(),
                  const SizedBox(height: 8),
                  SizedBox(height: 280, child: _buildCombinedChart(true)),
                  const SizedBox(height: 8),
                  SizedBox(height: 320, child: _buildRecentEvents(true)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _buildDesktopLayout() => Column(
        children: [
          _buildHeader(false),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 10),
                      _buildSensorRow(false),
                      const SizedBox(height: 10),
                      Expanded(child: _buildCombinedChart(false)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildRiskMeter(),
                      const SizedBox(height: 10),
                      _buildPredictions(false),
                      const SizedBox(height: 10),
                      _buildMitigation(),
                      const SizedBox(height: 10),
                      Expanded(child: _buildRecentEvents(false)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  // Enhanced Electric Logo with animated glow effect
  Widget _buildElectricLogo({required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5E9BFF), Color(0xFF00D2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5E9BFF).withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        child: Icon(
          Icons.flash_on_rounded,
          color: Colors.white,
          size: isMobile ? 24 : 32,
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A5F).withOpacity(0.95),
            const Color(0xFF0F172A).withOpacity(0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5E9BFF).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF5E9BFF).withOpacity(0.2),
        ),
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    _buildElectricLogo(isMobile: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Beyond The Bre4ker",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24)).withOpacity(0.5),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isConnected ? "LIVE" : "DEMO",
                                style: TextStyle(
                                  fontSize: 10,
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
                  ],
                ),
              ],
            )
          : Row(
              children: [
                _buildElectricLogo(isMobile: false),
                const SizedBox(width: 16),
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isConnected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24)).withOpacity(0.5),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            getStatusColor().withOpacity(0.15),
            getStatusColor().withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: getStatusColor().withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: getStatusColor().withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                    color: Colors.white.withOpacity(0.5),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: getStatusColor(),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [getStatusColor().withOpacity(0.2), getStatusColor().withOpacity(0.1)],
                    ),
                    borderRadius: BorderRadius.circular(20),
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
              gradient: LinearGradient(
                colors: [getStatusColor().withOpacity(0.2), getStatusColor().withOpacity(0.05)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(getStatusIcon(), size: 36, color: getStatusColor()),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorRow(bool isMobile) => Row(
        children: [
          Expanded(child: _buildSensorCard("TEMP", temperature.toStringAsFixed(1), "°C", Icons.thermostat, const Color(0xFF5E9BFF), temperature, 100)),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(child: _buildSensorCard("CURRENT", current.toStringAsFixed(1), "A", Icons.electric_bolt, const Color(0xFF2DD4BF), current, 100)),
        ],
      );

  Widget _buildSensorCard(String title, String value, String unit, IconData icon, Color color, double currentValue, double maxValue) {
    double progress = (currentValue / maxValue).clamp(0, 1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF11162E), const Color(0xFF0D1228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              TextSpan(text: unit, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
            ]),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedChart(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF11162E), const Color(0xFF0D1228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.timeline, size: 14, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text("METRICS TREND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5), letterSpacing: 0.5)),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF5E9BFF).withOpacity(0.2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMetric,
                    dropdownColor: const Color(0xFF1E1F3A),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF7CB9E8)),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.5), size: 16),
                    items: metrics.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (String? newValue) => setState(() => _selectedMetric = newValue!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: tempSpots.isEmpty
                ? Center(child: Text("Waiting for data...", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)))
                : LineChart(LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                      getDrawingVerticalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (value, meta) => value.toInt() % 5 == 0 && value >= 0 && value < dataPointIndex
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 9, color: Colors.white38)),
                                )
                              : const SizedBox(),
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) => Text("${(value * 100).toInt()}%", style: const TextStyle(fontSize: 9, color: Colors.white38)),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: Colors.white.withOpacity(0.05))),
                    minX: 0,
                    maxX: dataPointIndex > 0 ? dataPointIndex.toDouble() : 10,
                    minY: 0,
                    maxY: 1,
                    lineBarsData: _getChartLines(),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        tooltipBgColor: const Color(0xFF0A0E27),
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
                      ),
                    ),
                  )),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 4, alignment: WrapAlignment.center, children: [
            _buildLegend("Temp", const Color(0xFF5E9BFF)),
            _buildLegend("Current", const Color(0xFF2DD4BF)),
            _buildLegend("Hotspot", const Color(0xFFA78BFA)),
            _buildLegend("Overload", const Color(0xFFFBBF24)),
            _buildLegend("Risk", const Color(0xFFF87171)),
          ]),
        ],
      ),
    );
  }

  List<LineChartBarData> _getChartLines() {
    List<LineChartBarData> lines = [];
    if (_selectedMetric == 'All' || _selectedMetric == 'Temperature') lines.add(LineChartBarData(spots: tempSpots, isCurved: true, color: const Color(0xFF5E9BFF), barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false, color: const Color(0xFF5E9BFF).withOpacity(0.05))));
    if (_selectedMetric == 'All' || _selectedMetric == 'Current') lines.add(LineChartBarData(spots: currentSpots, isCurved: true, color: const Color(0xFF2DD4BF), barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false, color: const Color(0xFF2DD4BF).withOpacity(0.05))));
    if (_selectedMetric == 'All' || _selectedMetric == 'Hotspot') lines.add(LineChartBarData(spots: hotspotSpots, isCurved: true, color: const Color(0xFFA78BFA), barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false, color: const Color(0xFFA78BFA).withOpacity(0.05))));
    if (_selectedMetric == 'All' || _selectedMetric == 'Overload') lines.add(LineChartBarData(spots: overloadSpots, isCurved: true, color: const Color(0xFFFBBF24), barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false, color: const Color(0xFFFBBF24).withOpacity(0.05))));
    if (_selectedMetric == 'All' || _selectedMetric == 'Risk') lines.add(LineChartBarData(spots: riskSpots, isCurved: true, color: const Color(0xFFF87171), barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: false, color: const Color(0xFFF87171).withOpacity(0.05))));
    return lines;
  }

  Widget _buildLegend(String label, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)]),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
      ]);

  Widget _buildRiskMeter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF11162E), const Color(0xFF0D1228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("RISK INDEX", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5), letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${getRiskPercentage().toInt()}%", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: getStatusColor())),
                    const SizedBox(height: 4),
                    Text(getRiskLevel(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: getStatusColor())),
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
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation(getStatusColor()),
                    ),
                    Text("${getRiskPercentage().toInt()}%", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: getRiskPercentage() / 100,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: const AlwaysStoppedAnimation(Colors.transparent),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictions(bool isMobile) => Row(
        children: [
          Expanded(child: _buildPredictionCard("HOTSPOT", hotspotProb, const Color(0xFFA78BFA), Icons.local_fire_department)),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(child: _buildPredictionCard("OVERLOAD", overloadProb, const Color(0xFFFBBF24), Icons.electric_bolt)),
        ],
      );

  Widget _buildPredictionCard(String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF11162E), const Color(0xFF0D1228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          ]),
          const SizedBox(height: 8),
          Text("${(value * 100).toInt()}%", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMitigation() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A5F).withOpacity(0.25),
            const Color(0xFF0F172A).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5E9BFF).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5E9BFF).withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF7CB9E8), size: 18),
            ),
            const SizedBox(width: 10),
            const Text("SMART RECOMMENDATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF7CB9E8), letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Icon(status == "Normal" ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: getStatusColor(), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    recommendedAction,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white, height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEvents(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF11162E), const Color(0xFF0D1228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.history, size: 14, color: Colors.white.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text("RECENT EVENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5), letterSpacing: 0.5)),
                ]),
                Row(children: [
                  if (historyLog.isNotEmpty) _buildActionButton("All", Icons.list_alt, const Color(0xFF5E9BFF), () => _viewFullHistory()),
                  const SizedBox(width: 6),
                  if (historyLog.isNotEmpty) _buildActionButton("Clear", Icons.delete_outline, const Color(0xFFF87171), () => _clearHistory()),
                ]),
              ],
            ),
          ),
          Expanded(
            child: historyLog.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.history, size: 40, color: Colors.white.withOpacity(0.05)),
                    const SizedBox(height: 8),
                    Text("No data yet", style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: historyLog.length > 8 ? 8 : historyLog.length,
                    itemBuilder: (context, index) => _buildEventItem(historyLog[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _buildEventItem(HistoryEntry entry) {
    final statusColor = entry.status == "Normal" ? const Color(0xFF4ADE80) : (entry.status == "Warning" ? const Color(0xFFFBBF24) : (entry.status == "Overload" ? const Color(0xFFFB923C) : const Color(0xFFF87171)));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(entry.status == "Normal" ? Icons.check_circle : (entry.status == "Warning" ? Icons.warning_amber : (entry.status == "Overload" ? Icons.electric_bolt : Icons.whatshot)), color: statusColor, size: 14),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor)),
          const SizedBox(height: 2),
          Text("${entry.temperature.toStringAsFixed(1)}°C • ${entry.current.toStringAsFixed(1)}A", style: const TextStyle(fontSize: 8, color: Colors.white54)),
        ])),
        Text(DateFormat('HH:mm').format(entry.timestamp), style: const TextStyle(fontSize: 9, color: Color(0xFF7CB9E8), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _viewFullHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF11162E), Color(0xFF0A0E27)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(Icons.history, size: 20, color: const Color(0xFF5E9BFF)),
                    const SizedBox(width: 10),
                    Text("FULL HISTORY (${historyLog.length})", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ]),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 20)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: historyLog.length,
                itemBuilder: (context, index) {
                  final entry = historyLog[index];
                  final statusColor = entry.status == "Normal" ? const Color(0xFF4ADE80) : (entry.status == "Warning" ? const Color(0xFFFBBF24) : (entry.status == "Overload" ? const Color(0xFFFB923C) : const Color(0xFFF87171)));
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Icon(entry.status == "Normal" ? Icons.check_circle : (entry.status == "Warning" ? Icons.warning_amber : (entry.status == "Overload" ? Icons.electric_bolt : Icons.whatshot)), color: statusColor, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(entry.status.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                                const SizedBox(height: 2),
                                Text(DateFormat('MMM dd, yyyy').format(entry.timestamp), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                              ]),
                            ]),
                            Text(DateFormat('HH:mm:ss').format(entry.timestamp), style: const TextStyle(fontSize: 12, color: Color(0xFF7CB9E8), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _buildDetailChip("Temp", "${entry.temperature.toStringAsFixed(1)}°C", const Color(0xFF5E9BFF)),
                          _buildDetailChip("Current", "${entry.current.toStringAsFixed(1)}A", const Color(0xFF2DD4BF)),
                          _buildDetailChip("Hotspot", "${(entry.hotspotProb * 100).toInt()}%", const Color(0xFFA78BFA)),
                          _buildDetailChip("Overload", "${(entry.overloadProb * 100).toInt()}%", const Color(0xFFFBBF24)),
                          _buildDetailChip("Risk", "${(entry.compositeRisk * 100).toInt()}%", const Color(0xFFF87171)),
                        ]),
                        if (entry.recommendedAction.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A5F).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1E3A5F).withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              Icon(Icons.lightbulb, size: 12, color: const Color(0xFF7CB9E8)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(entry.recommendedAction, style: const TextStyle(fontSize: 9, color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        ],
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

  Widget _buildDetailChip(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ]),
      );

  void _clearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF11162E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear History", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to clear all history logs?", style: TextStyle(color: Colors.white, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
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
            child: const Text("Clear", style: TextStyle(color: Color(0xFFF87171), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}