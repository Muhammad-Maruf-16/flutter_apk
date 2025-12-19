import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Menghilangkan banner debug
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF662A00),
          foregroundColor: Colors.white,
        ),
      ),
      home: const AndroidCompact1(),
    );
  }
}

// Model data dan event
class SensorDataPoint {
  final double time;
  final double temperature;
  SensorDataPoint(this.time, this.temperature);
}

class RoastEvent {
  final String label;
  final int secondsElapsed;
  final double btTemp;
  RoastEvent(this.label, this.secondsElapsed, this.btTemp);

  // Fungsi copyWith diperlukan untuk pembaruan status Turning Point
  RoastEvent copyWith({
    String? label,
    int? secondsElapsed,
    double? btTemp,
  }) {
    return RoastEvent(
      label ?? this.label,
      secondsElapsed ?? this.secondsElapsed,
      btTemp ?? this.btTemp,
    );
  }
}

class AndroidCompact1 extends StatefulWidget {
  const AndroidCompact1({super.key});

  @override
  State<AndroidCompact1> createState() => _AndroidCompact1State();
}

class _AndroidCompact1State extends State<AndroidCompact1> {
  bool _isRunning = false;
  Timer? _timer;
  int _secondsElapsed = 0;
  int _phaseStartTimeInSeconds = 0;
  Key _scaffoldKey = UniqueKey();

  double _btTemp = 0.0;
  double _etTemp = 0.0;
  double _ror = 0.0;

  final List<SensorDataPoint> _btData = [];
  final List<SensorDataPoint> _etData = [];
  final List<SensorDataPoint> _rorData = [];
  final List<RoastEvent> _recordedEvents = [];

  // Variabel untuk melacak Turning Point otomatis
  RoastEvent? _turningPoint;

  final Map<String, bool> _eventStatus = {
    'CHARGE': false,
    'DRY END': false,
    '1st CRACK': false,
    '2nd CRACK': false,
    'DROP': false,
    'COOL END': false,
  };

  StreamSubscription? _dataSubscription;

  String _formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  // --- FUNGSI NOTIFIKASI TURNING POINT ---
  void _showTurningPointNotification(RoastEvent tp) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text(
            '🔥 TURNING POINT DITEMUKAN! 🔥\nWaktu: ${_formatTime(tp.secondsElapsed)} | Suhu BT: ${tp.btTemp.toStringAsFixed(1)} °C',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // --- FUNGSI SENSOR (SIMULASI) DAN DATA RECEIVE ---
  Future<void> _connectToSensor() async {
    final sensorStream =
        Stream.periodic(const Duration(milliseconds: 500), (count) {
      if (!_isRunning) return 'BT:0.0,ET:0.0';
      final timeInMinutes = _secondsElapsed / 60.0;

      // SIMULASI DATA (Disesuaikan untuk memicu TP dan kenaikan suhu)
      final simulatedBt = _secondsElapsed < 15
          ? (100.0 - (_secondsElapsed * 2.5))
          : // BT turun drastis di awal
          (62.5 + (timeInMinutes * 15.0)); // BT mulai naik perlahan

      final simulatedEt = 60.0 + (timeInMinutes * 18.0);
      return 'BT:${simulatedBt.toStringAsFixed(1)},ET:${simulatedEt.toStringAsFixed(1)}';
    }).take(10000);

    // Ganti bagian ini dengan koneksi sensor fisik (Bluetooth/Serial)
    _dataSubscription = sensorStream.listen(
      _receiveDataStream,
      onError: (e) => debugPrint("Error data stream: $e"),
      onDone: () => debugPrint("Koneksi sensor terputus (simulasi selesai)."),
    );
  }

  void _receiveDataStream(String data) {
    try {
      final parts = data.split(',');
      final newBt = double.tryParse(parts.first.split(':')[1]) ?? _btTemp;
      final newEt = double.tryParse(parts.last.split(':')[1]) ?? _etTemp;

      // RoR sederhana (Perlu penyempurnaan di aplikasi nyata)
      final currentRor = newEt - newBt;
      final currentRorFixed = double.parse(currentRor.toStringAsFixed(1));

      setState(() {
        _btTemp = newBt;
        _etTemp = newEt;
        _ror = currentRorFixed;

        final timeInMinutes = _secondsElapsed / 60.0;
        _btData.add(SensorDataPoint(timeInMinutes, _btTemp));
        _etData.add(SensorDataPoint(timeInMinutes, _etTemp));
        _rorData.add(SensorDataPoint(timeInMinutes, _ror));

        _checkTurningPoint();
      });
    } catch (e) {
      debugPrint('Error parsing data sensor: $e');
    }
  }

  // FUNGSI UNTUK MENCARI DAN MENGUNCI TURNING POINT SECARA OTOMATIS
  void _checkTurningPoint() {
    final isChargeStarted = _eventStatus['CHARGE'] == true;

    if (isChargeStarted && _turningPoint?.label != 'TP Locked') {
      if (_btData.length > 1) {
        final previousBt = _btData[_btData.length - 2].temperature;

        // 1. Suhu BT masih turun atau sama (cari titik terendah)
        if (_btTemp <= previousBt) {
          _turningPoint = RoastEvent('TP Potential', _secondsElapsed, _btTemp);
        }
        // 2. Suhu sudah mulai naik signifikan (> 1.0°C) dari titik terendah TP
        else if (_turningPoint != null &&
            _btTemp > (_turningPoint!.btTemp + 1.0)) {
          // TP DITEMUKAN DAN DIKUNCI
          final finalTp = RoastEvent('TURNING POINT',
              _turningPoint!.secondsElapsed, _turningPoint!.btTemp);

          if (!_recordedEvents
              .any((e) => e.label.startsWith('TURNING POINT'))) {
            _recordedEvents.add(finalTp);
            _turningPoint = finalTp.copyWith(label: 'TP Locked');
            debugPrint(
                'TURNING POINT DITEMUKAN: ${_formatTime(finalTp.secondsElapsed)} di ${finalTp.btTemp.toStringAsFixed(1)}°C');

            // PANGGIL NOTIFIKASI
            _showTurningPointNotification(finalTp);
          }
        }
      }
    }
  }

  // --- LOGIKA KONTROL (START/STOP/RESET/EVENT) ---
  void _toggleRunState() {
    if (_isRunning) {
      _timer?.cancel();
      _dataSubscription?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _secondsElapsed++;
        });
      });
      _connectToSensor();
    }
    setState(() {
      _isRunning = !_isRunning;
    });
  }

  void _resetState() {
    _timer?.cancel();
    _dataSubscription?.cancel();
    setState(() {
      _isRunning = false;
      _secondsElapsed = 0;
      _phaseStartTimeInSeconds = 0;
      _btTemp = 0.0;
      _etTemp = 0.0;
      _ror = 0.0;
      _btData.clear();
      _etData.clear();
      _rorData.clear();
      _recordedEvents.clear();
      _turningPoint = null; // Reset TP
      _eventStatus.updateAll((key, value) => false);
    });
  }

  void _refreshScreen() {
    setState(() {
      _scaffoldKey = UniqueKey();
    });
  }

  void _toggleEventButton(String eventLabel) {
    if (!_isRunning) return;
    setState(() {
      final currentState = _eventStatus[eventLabel] ?? false;
      if (!currentState) {
        _eventStatus[eventLabel] = true;
        _phaseStartTimeInSeconds = _secondsElapsed;
        _recordedEvents.add(RoastEvent(eventLabel, _secondsElapsed, _btTemp));
      } else {
        _eventStatus[eventLabel] = false;
        // Hanya hapus event manual, TP tidak boleh dihapus
        if (!eventLabel.startsWith('TURNING POINT')) {
          _recordedEvents.removeWhere((e) => e.label == eventLabel);
        }
      }
    });
  }

  // =========================================================
  // FUNGSI LOG EVENT (Dilengkapi dengan tampilan TP)
  // =========================================================
  void _showEventLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Riwayat Event Roasting',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF662A00)),
              ),
              const Divider(thickness: 2),
              if (_recordedEvents.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20.0),
                  child: Center(child: Text('Belum ada event yang dicatat.')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _recordedEvents.length,
                    itemBuilder: (context, index) {
                      final event = _recordedEvents[index];
                      final isTp = event.label.startsWith('TURNING POINT');
                      final cardColor =
                          isTp ? Colors.red.shade50 : Colors.white;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 2,
                        color: cardColor,
                        child: ListTile(
                          leading: Icon(
                            isTp ? Icons.star : Icons.history,
                            color: isTp
                                ? Colors.red.shade900
                                : Theme.of(context).primaryColor,
                          ),
                          title: Text(
                            event.label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isTp ? Colors.red.shade900 : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            'Waktu: ${_formatTime(event.secondsElapsed)} | Suhu BT: ${event.btTemp.toStringAsFixed(1)} °C',
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // FUNGSI DOT MARKER KUSTOM UNTUK TP dan Event Manual
  // =========================================================
  FlDotData _buildEventDots() {
    return FlDotData(
      show: true,
      getDotPainter: (spot, percent, barData, index) {
        final timeInSeconds = spot.x * 60;

        RoastEvent? foundEvent;
        for (var event in _recordedEvents) {
          if ((timeInSeconds - event.secondsElapsed).abs() < 1) {
            foundEvent = event;
            break;
          }
        }

        final isEventSpot = foundEvent != null;
        final isTpSpot = foundEvent?.label.startsWith('TURNING POINT') ?? false;

        if (isEventSpot) {
          final color =
              isTpSpot ? Colors.red.shade900 : const Color(0xFFFFB22C);
          return FlDotCirclePainter(
            radius: isTpSpot ? 7.0 : 6.0,
            color: color,
            strokeColor: Colors.black,
            strokeWidth: 2,
          );
        }
        return FlDotCirclePainter(radius: 0);
      },
    );
  }

  // --- FUNGSI GARIS VERTIKAL MARKER ---
  List<VerticalLine> _buildEventMarkers() {
    return _recordedEvents.map((event) {
      final xValue = event.secondsElapsed / 60.0;
      final isTp = event.label.startsWith('TURNING POINT');

      return VerticalLine(
        x: xValue,
        color: isTp ? Colors.red.shade400 : Colors.black,
        strokeWidth: 1.5,
        dashArray: [5, 5],
      );
    }).toList();
  }

  // --- FUNGSI DATA GARIS GRAFIK ---
  LineChartBarData _buildLineBarData(
      List<SensorDataPoint> data, Color color, String name) {
    final FlDotData dotData =
        (name == 'BT') ? _buildEventDots() : const FlDotData(show: false);

    return LineChartBarData(
      spots:
          data.map((point) => FlSpot(point.time, point.temperature)).toList(),
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: dotData,
      belowBarData: BarAreaData(show: false),
    );
  }

  // =========================================================
  // FUNGSI GRAFIK UTAMA: PERBAIKAN min Y
  // =========================================================
  Widget _buildMainContentArea() {
    if (_btData.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
          boxShadow: const [
            BoxShadow(
                color: Color(0x3F000000), blurRadius: 4, offset: Offset(0, 4)),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          "Area Grafik Data Roasting\n(Tekan START untuk memulai)",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
          right: 18.0, left: 12.0, top: 24.0, bottom: 12.0),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (_secondsElapsed / 60.0) + 1.0,
          minY: -5, // <-- Disesuaikan agar RoR negatif tidak keluar dari batas
          maxY: 350,
          titlesData: FlTitlesData(
            show: true,
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget:
                  const Text('Waktu (min)', style: TextStyle(fontSize: 10)),
              axisNameSize: 15,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 2,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget:
                  const Text('Suhu (°C)', style: TextStyle(fontSize: 10)),
              axisNameSize: 15,
              sideTitles: SideTitles(
                showTitles: true,
                interval: 50,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  // Hanya tampilkan label jika nilai >= 0
                  if (value < 0) return Container();
                  if (value % 50 != 0) return Container();
                  return Text('${value.toInt()}',
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 50,
            verticalInterval: 2,
            getDrawingHorizontalLine: (value) =>
                const FlLine(color: Color(0xffececec), strokeWidth: 0.5),
            getDrawingVerticalLine: (value) =>
                const FlLine(color: Color(0xffececec), strokeWidth: 0.5),
          ),
          borderData: FlBorderData(
              show: true,
              border: Border.all(color: const Color(0xff37434d), width: 1)),
          extraLinesData: ExtraLinesData(
            verticalLines: _buildEventMarkers(),
          ),
          lineBarsData: [
            _buildLineBarData(_btData, Colors.red, 'BT'),
            _buildLineBarData(_etData, Colors.blue, 'ET'),
            _buildLineBarData(_rorData, Colors.green, 'RoR'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('EIKO COFFE ROASTED',
            style: TextStyle(
                fontSize: 20,
                fontFamily: 'Merriweather Sans',
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.more_vert), onPressed: _showEventLog),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTimeAndDurationSection(),
            const SizedBox(height: 8),
            _buildTempSection(),
            const SizedBox(height: 8),
            Expanded(child: _buildMainContentArea()),
            const SizedBox(height: 8),
            _buildCrackSection(),
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- FUNGSI UI LAINNYA ---
  Widget _buildTempSection() {
    return Row(
      children: [
        Expanded(
            child:
                _buildTempBox('BT (°C)', '${_btTemp.toStringAsFixed(1)} °C')),
        const SizedBox(width: 8),
        Expanded(
            child:
                _buildTempBox('ET (°C)', '${_etTemp.toStringAsFixed(1)} °C')),
        const SizedBox(width: 8),
        Expanded(child: _buildTempBox('RoR (C/m)', _ror.toStringAsFixed(1))),
      ],
    );
  }

  Widget _buildTimeAndDurationSection() {
    int currentDuration = _secondsElapsed - _phaseStartTimeInSeconds;
    if (currentDuration < 0) currentDuration = 0;
    if (!_isRunning && _phaseStartTimeInSeconds == 0) currentDuration = 0;
    final durationDisplay = _formatTime(currentDuration);

    return Row(
      children: [
        Expanded(
            child: Container(
          height: 48,
          decoration: BoxDecoration(
              color: const Color(0xFF662A00),
              borderRadius: BorderRadius.circular(9)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('TIME',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w500)),
            Text(_formatTime(_secondsElapsed),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w500)),
          ]),
        )),
        const SizedBox(width: 8),
        Expanded(
            child: Container(
          height: 48,
          decoration: BoxDecoration(
              color: const Color(0xFF662A00),
              borderRadius: BorderRadius.circular(9)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('DURATION',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w500)),
            Text(durationDisplay,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w500)),
          ]),
        )),
      ],
    );
  }

  Widget _buildTempBox(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(4),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF662A00), width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 1),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCrackSection() {
    return Column(
      children: [
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('00:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('02:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('04:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('06:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('08:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('10:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('12:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('14:00', style: TextStyle(color: Colors.black, fontSize: 9)),
          Text('15:50', style: TextStyle(color: Colors.black, fontSize: 9)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _buildActionButton('CHARGE', 1),
          _buildActionButton('DRY END', 1),
          _buildActionButton('1st CRACK', 1),
          _buildActionButton('2nd CRACK', 1),
          _buildActionButton('DROP', 1),
          _buildActionButton('COOL END', 1),
        ]),
      ],
    );
  }

  Widget _buildActionButton(String label, int flex) {
    final isToggled = _eventStatus[label] ?? false;
    final backgroundColor =
        isToggled ? const Color(0xFF662A00) : Colors.transparent;
    final textColor = isToggled ? Colors.white : Colors.black;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: GestureDetector(
          onTap: () => _toggleEventButton(label),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: backgroundColor,
              border: Border.all(color: const Color(0xFF662A00), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(children: [
          _buildMainButton(_isRunning ? 'STOP' : 'START',
              _isRunning ? Colors.red : const Color(0xFFFFB22C),
              onPressed: _toggleRunState),
          const SizedBox(width: 8),
          _buildMainButton('RESET', const Color(0xFFFFB22C),
              onPressed: _resetState),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildMainButton('REFRESH', const Color(0xFFFFB22C),
              onPressed: _refreshScreen),
        ]),
      ],
    );
  }

  Widget _buildMainButton(String label, Color color,
      {int flex = 1, VoidCallback? onPressed}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(width: 1)),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
