import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String serviceUuid =
    '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

const String characteristicUuid =
    '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

void main() {
  runApp(const EggPamApp());
}

class EggPamApp extends StatelessWidget {
  const EggPamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'เครื่องเก็บไข่ผำ',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? characteristic;

  StreamSubscription<List<ScanResult>>? scanSub;
  StreamSubscription<BluetoothConnectionState>? connectionSub;

  List<ScanResult> results = [];

  bool scanning = false;
  bool connected = false;

  String status = 'ยังไม่ได้เชื่อมต่อ';

  @override
  void dispose() {
    scanSub?.cancel();
    connectionSub?.cancel();
    super.dispose();
  }

  Future<void> scan() async {
    if (scanning) return;

    setState(() {
      scanning = true;
      results = [];
      status = 'กำลังค้นหา ESP32...';
    });

    try {
      await scanSub?.cancel();

      scanSub = FlutterBluePlus.scanResults.listen((list) {
        if (!mounted) return;

        final Map<String, ScanResult> unique = {};

        for (final r in list) {
          final id = r.device.remoteId.toString();

          if (r.device.platformName.isNotEmpty) {
            unique[id] = r;
          }
        }

        setState(() {
          results = unique.values.toList();
        });
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );

      await Future.delayed(
        const Duration(milliseconds: 300),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'ค้นหาไม่สำเร็จ: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          scanning = false;

          if (results.isEmpty) {
            status = 'ไม่พบ ESP32';
          }
        });
      }
    }
  }

  Future<void> connectToDevice(
    BluetoothDevice selected,
  ) async {
    try {
      setState(() {
        status = 'กำลังเชื่อมต่อ...';
      });

      await FlutterBluePlus.stopScan();

      await connectionSub?.cancel();

      connectionSub = selected.connectionState.listen((state) {
        if (!mounted) return;

        setState(() {
          connected =
              state == BluetoothConnectionState.connected;
        });
      });

      await selected.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );

      final services =
          await selected.discoverServices();

      BluetoothCharacteristic? found;

      for (final service in services) {
        if (service.uuid.toString().toUpperCase() ==
            serviceUuid.toUpperCase()) {
          for (final c in service.characteristics) {
            if (c.uuid.toString().toUpperCase() ==
                characteristicUuid.toUpperCase()) {
              found = c;
              break;
            }
          }
        }

        if (found != null) break;
      }

      if (found == null) {
        await selected.disconnect();

        if (mounted) {
          setState(() {
            connected = false;
            status =
                'เชื่อมต่อได้ แต่ไม่พบ Characteristic';
          });
        }

        return;
      }

      if (!mounted) return;

      setState(() {
        device = selected;
        characteristic = found;
        connected = true;
        status = 'เชื่อมต่อ ESP32 แล้ว';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          connected = false;
          status = 'เชื่อมต่อไม่สำเร็จ: $e';
        });
      }
    }
  }

  Future<void> disconnect() async {
    try {
      await device?.disconnect();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      device = null;
      characteristic = null;
      connected = false;
      status = 'ตัดการเชื่อมต่อแล้ว';
    });
  }

  Future<void> send(String command) async {
    if (!connected || characteristic == null) {
      setState(() {
        status = 'ยังไม่ได้เชื่อมต่อ ESP32';
      });
      return;
    }

    try {
      await characteristic!.write(
        Uint8List.fromList(command.codeUnits),
        withoutResponse: false,
      );

      if (!mounted) return;

      setState(() {
        status = 'ส่งคำสั่ง $command';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'ส่งคำสั่งไม่สำเร็จ: $e';
        });
      }
    }
  }

  Widget button(
    String text,
    String command,
    IconData icon,
  ) {
    return SizedBox(
      width: 105,
      height: 70,
      child: ElevatedButton(
        onPressed:
            connected ? () => send(command) : null,
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(height: 3),
            Text(text),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เครื่องเก็บไข่ผำ'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.bluetooth,
                        size: 55,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                scanning ? null : scan,
                            icon: const Icon(Icons.search),
                            label: Text(
                              scanning
                                  ? 'กำลังค้นหา'
                                  : 'ค้นหา ESP32',
                            ),
                          ),
                          if (connected) ...[
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: disconnect,
                              icon: const Icon(
                                Icons.link_off,
                              ),
                              label: const Text('ตัดการเชื่อมต่อ'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),

              if (results.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'อุปกรณ์ที่พบ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...results.map(
                        (r) => ListTile(
                          leading:
                              const Icon(Icons.bluetooth),
                          title: Text(
                            r.device.platformName,
                          ),
                          subtitle: Text(
                            r.device.remoteId.toString(),
                          ),
                          trailing: ElevatedButton(
                            onPressed: connected
                                ? null
                                : () => connectToDevice(
                                      r.device,
                                    ),
                            child:
                                const Text('เชื่อมต่อ'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              const Text(
                'ควบคุมเครื่อง',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              button(
                'เดินหน้า',
                'F',
                Icons.arrow_upward,
              ),

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  button(
                    'ซ้าย',
                    'L',
                    Icons.arrow_back,
                  ),
                  const SizedBox(width: 8),
                  button(
                    'หยุด',
                    'S',
                    Icons.stop,
                  ),
                  const SizedBox(width: 8),
                  button(
                    'ขวา',
                    'R',
                    Icons.arrow_forward,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              button(
                'ถอยหลัง',
                'B',
                Icons.arrow_downward,
              ),

              const SizedBox(height: 20),

              const Text(
                'F เดินหน้า   B ถอยหลัง   L ซ้าย   R ขวา   S หยุด',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
