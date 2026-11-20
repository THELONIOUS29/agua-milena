import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'datos/servicios/servicio_notificacion.dart';
import 'datos/servicios/servicio_info_dispositivo.dart';
import 'datos/servicios/servicio_reporte_errores.dart';
import 'nucleo/configuracion/configuracion_supabase.dart';
import 'nucleo/enrutador/enrutador_app.dart';
import 'nucleo/tema/tema_app.dart';
import 'nucleo/constantes/colores_app.dart';
import 'presentacion/componentes/verificador_app.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (!SupabaseConfig.isConfigured) {
        runApp(const _ConfigErrorApp());
        return;
      }

      final firebaseInit = _inicializarFirebaseYNotificaciones();
      await Future.wait([
        initializeDateFormatting('es', null),
        Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: SupabaseConfig.anonKey,
        ),
        firebaseInit,
      ]);

      try {
        await ServicioInfoDispositivo.instance.inicializar();
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ DeviceInfo no inicializado: $e');
      }

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        ServicioReporteErrores.instance.reportarErrorFlutter(details);
      };

      runApp(const ProviderScope(child: AguaMilenaApp()));
    },
    (error, stack) {
      ServicioReporteErrores.instance.reportarError(error, stack);
    },
  );
}

Future<void> _inicializarFirebaseYNotificaciones() async {
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          authDomain: 'agua-milena.firebaseapp.com',
          projectId: 'agua-milena',
          storageBucket: 'agua-milena.firebasestorage.app',
          messagingSenderId: '504410173979',
          appId: '1:504410173979:web:d826d0dd9aa1cf68e2febe',
          measurementId: 'G-P31SKZG7JD',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
    await ServicioNotificacion().inicializar();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase/Notificaciones no inicializadas: $e');
    }
  }
}

class AguaMilenaApp extends ConsumerWidget {
  const AguaMilenaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(proveedorEnrutador);

    return MaterialApp.router(
      title: 'Agua Milena',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: goRouter,
      builder: (context, child) =>
          VerificadorApp(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Configuración incompleta',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Falta definir SUPABASE_URL y SUPABASE_ANON_KEY.\n\n'
                  'Ejecuta con:\nflutter run '
                  '--dart-define=SUPABASE_URL=<tu-url> '
                  '--dart-define=SUPABASE_ANON_KEY=<tu-key>',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
