import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FutureBuilder<String>(
            future: testLoad(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Loading library...'),
                  ],
                );
              }
              
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              
              return Text(
                snapshot.data ?? 'Unknown',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<String> testLoad() async {
  try {
    print('🔍 Attempting to load library...');
    
    // Полный путь к библиотеке
    final libraryPath = '/Volumes/Dev/projects/hivra/target/release/libhivra_ffi.dylib';
    print('📁 Library path: $libraryPath');
    
    // Проверим, существует ли файл
    final file = File(libraryPath);
    if (!await file.exists()) {
      return '❌ Library file not found at:\n$libraryPath';
    }
    print('✅ Library file exists');
    
    // Попробуем загрузить
    final lib = DynamicLibrary.open(libraryPath);
    print('✅ Library loaded successfully');
    
    // Проверим символы
    try {
      lib.lookup<NativeFunction<Pointer<Char> Function()>>('hivra_key_generate');
      print('✅ Symbol hivra_key_generate found');
    } catch (e) {
      return '❌ Symbol hivra_key_generate not found: $e';
    }
    
    try {
      lib.lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Uint8>, IntPtr)>>('hivra_sign');
      print('✅ Symbol hivra_sign found');
    } catch (e) {
      return '❌ Symbol hivra_sign not found: $e';
    }
    
    return '✅ SUCCESS!\nLibrary loaded and all symbols found';
  } catch (e) {
    print('❌ Error: $e');
    return '❌ Failed: $e';
  }
}
