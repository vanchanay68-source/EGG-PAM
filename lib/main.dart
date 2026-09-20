import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const WoffiaHarvesterApp());
}

class WoffiaHarvesterApp extends StatelessWidget {
  const WoffiaHarvesterApp({super.key});

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
  // ============================================================
  // ESP32 BLE UUID
  // ============================================================

  static final Guid serviceUuid =
      Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");

  static final Guid characteristicUuid =
      Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");

  // ============================================================
  // Bluetooth
  // ============================================================

  BluetoothDevice? device;
  BluetoothCharacteristic? commandCharacteristic;

  StreamSubscription<List<ScanResult>>? scanSubscription;
  StreamSubscription<BluetoothConnectionState>? connectionSubscription;

  bool scanning = false;
  bool connected = false;

  String status = "ยังไม่ได้เชื่อมต่อ";
  String deviceName = "-";

  List<ScanResult> scanResults = [];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;

      if (state != BluetoothAdapterState.on) {
        setState(() {
          connected = false;
          status = "กรุณาเปิด Bluetooth";
        });
      }
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();

    if (device != null) {
      device!.disconnect();
    }

    super.dispose();
  }

  // ============================================================
  // SCAN BLE
  // ============================================================

  Future<void> scanDevices() async {
    if (scanning) return;

    setState(() {
      scanning = true;
      scanResults.clear();
      status = "กำลังค้นหา ESP32...";
    });

    try {
      await FlutterBluePlus.stopScan();

      scanSubscription?.cancel();

      scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          if (!mounted) return;

          final Map<String, ScanResult> uniqueDevices = {};

          for (final result in results) {
            uniqueDevices[result.device.remoteId.toString()] = result;
          }

          setState(() {
            scanResults = uniqueDevices.values.toList();
          });
        },
        onError: (error) {
          if (!mounted) return;

          setState(() {
            status = "เกิดข้อผิดพลาดในการค้นหา";
          });
        },
      );

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 6),
      );

      if (!mounted) return;

      setState(() {
        scanning = false;
        status = scanResults.isEmpty
            ? "ไม่พบ ESP32"
            : "พบอุปกรณ์ ${scanResults.length} เครื่อง";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        scanning = false;
        status = "สแกนไม่ได้: $e";
      });
    }
  }

  // ============================================================
  // CONNECT
  // ============================================================

  Future<void> connectToDevice(BluetoothDevice selectedDevice) async {
    try {
      await FlutterBluePlus.stopScan();

      setState(() {
        status = "กำลังเชื่อมต่อ...";
      });

      device = selectedDevice;

      connectionSubscription?.cancel();

      connectionSubscription = selectedDevice.connectionState.listen(
        (state) {
          if (!mounted) return;

          if (state == BluetoothConnectionState.connected) {
            setState(() {
              connected = true;
              status = "เชื่อมต่อแล้ว";
            });
          }

          if (state == BluetoothConnectionState.disconnected) {
            setState(() {
              connected = false;
              commandCharacteristic = null;
              status = "ตัดการเชื่อมต่อแล้ว";
            });
          }
        },
      );

      await selectedDevice.connect(
        timeout: const Duration(seconds: 10),
      );

      final services = await selectedDevice.discoverServices();

      BluetoothCharacteristic? foundCharacteristic;

      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid == characteristicUuid) {
              foundCharacteristic = characteristic;
              break;
            }
          }
        }

        if (foundCharacteristic != null) {
          break;
        }
      }

      if (foundCharacteristic == null) {
        await selectedDevice.disconnect();

        setState(() {
          connected = false;
          status = "ไม่พบ Characteristic ของ ESP32";
        });

        return;
      }

      commandCharacteristic = foundCharacteristic;

      final name = selectedDevice.platformName;

      setState(() {
        connected = true;
        deviceName = name.isEmpty ? "ESP32" : name;
        status = "เชื่อมต่อ ESP32 สำเร็จ";
      });
    } catch (e) {
      setState(() {
        connected = false;
        commandCharacteristic = null;
        status = "เชื่อมต่อไม่สำเร็จ";
      });
    }
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> disconnectDevice() async {
    try {
      await device?.disconnect();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      connected = false;
      commandCharacteristic = null;
      deviceName = "-";
      status = "ตัดการเชื่อมต่อแล้ว";
    });
  }

  // ============================================================
  // SEND COMMAND
  // ============================================================

  Future<void> sendCommand(String command) async {
    if (!connected || commandCharacteristic == null) {
      return;
    }

    try {
      final Uint8List data =
          Uint8List.fromList(utf8.encode(command));

      await commandCharacteristic!.write(
        data,
        withoutResponse: false,
      );

      if (!mounted) return;

      setState(() {
        status = "ส่งคำสั่ง: $command";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = "ส่งคำสั่งไม่สำเร็จ";
      });
    }
  }

  // ============================================================
  // CONTROL BUTTON
  // ============================================================

  Widget controlButton({
    required String text,
    required IconData icon,
    required String command,
    double size = 90,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: connected
            ? () {
                sendCommand(command);
              }
            : null,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 5),
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DEVICE LIST
  // ============================================================

  Widget deviceList() {
    if (scanResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          "กดค้นหาเพื่อค้นหา ESP32",
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: scanResults.map((result) {
        final name = result.device.platformName.isEmpty
            ? "อุปกรณ์ BLE"
            : result.device.platformName;

        return Card(
          child: ListTile(
            leading: const Icon(
              Icons.bluetooth,
              size: 32,
            ),
            title: Text(name),
            subtitle: Text(
              "${result.device.remoteId}\nRSSI: ${result.rssi}",
            ),
            trailing: ElevatedButton(
              onPressed: () {
                connectToDevice(result.device);
              },
              child: const Text("เชื่อมต่อ"),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "เครื่องเก็บไข่ผำ",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [

              // ------------------------------------------------
              // STATUS
              // ------------------------------------------------

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                            connected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            color: connected
                                ? Colors.green
                                : Colors.red,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            connected
                                ? "เชื่อมต่อแล้ว"
                                : "ยังไม่เชื่อมต่อ",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: connected
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Text(
                        "อุปกรณ์: $deviceName",
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        status,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // SCAN / DISCONNECT
              // ------------------------------------------------

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          scanning ? null : scanDevices,
                      icon: const Icon(Icons.search),
                      label: Text(
                        scanning
                            ? "กำลังค้นหา..."
                            : "ค้นหา ESP32",
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          connected ? disconnectDevice : null,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text("ตัดการเชื่อมต่อ"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ------------------------------------------------
              // DEVICE LIST
              // ------------------------------------------------

              deviceList(),

              const SizedBox(height: 20),

              const Text(
                "ควบคุมเครื่อง",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // FORWARD
              // ------------------------------------------------

              controlButton(
                text: "เดินหน้า",
                icon: Icons.arrow_upward,
                command: "F",
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // LEFT / STOP / RIGHT
              // ------------------------------------------------

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [

                  controlButton(
                    text: "ซ้าย",
                    icon: Icons.arrow_back,
                    command: "L",
                  ),

                  const SizedBox(width: 15),

                  SizedBox(
                    width: 90,
                    height: 90,
                    child: ElevatedButton(
                      onPressed: connected
                          ? () {
                              sendCommand("S");
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                      ),
                      child: const Text(
                        "หยุด",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 15),

                  controlButton(
                    text: "ขวา",
                    icon: Icons.arrow_forward,
                    command: "R",
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // ------------------------------------------------
              // REVERSE
              // ------------------------------------------------

              controlButton(
                text: "ถอยหลัง",
                icon: Icons.arrow_downward,
                command: "B",
              ),

              const SizedBox(height: 25),

              // ------------------------------------------------
              // COMMAND INFORMATION
              // ------------------------------------------------

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: const [
                      Text(
                        "คำสั่งที่ส่งไป ESP32",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text("F = เดินหน้า"),
                      Text("B = ถอยหลัง"),
                      Text("L = เลี้ยวซ้าย"),
                      Text("R = เลี้ยวขวา"),
                      Text("S = หยุด"),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
