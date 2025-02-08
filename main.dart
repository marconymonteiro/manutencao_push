import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'truck_list_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeApp();
  runApp(const MaintenanceApp());
}

/// Função para inicializar Firebase e outras configurações antes de rodar o app.
Future<void> initializeApp() async {
  try {
    // Inicializa o Firebase
    await Firebase.initializeApp();

    // Habilita a persistência offline do Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // Inscreve no tópico de notificações FCM
    await FirebaseMessaging.instance.subscribeToTopic('manutencao');
    print('Inscrito no tópico "manutencao"');

    // Solicita permissão para notificações
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final String? token = await messaging.getToken();
    if (token != null) {
      print("FCM Token: $token");
    } else {
      print("Erro ao obter o FCM Token.");
    }

    // ARMAZENA NOTIFICAÇÕES NO FIREBASE

    void _onMessageHandler(RemoteMessage message) {
      if (message.notification != null) {
        FirebaseFirestore.instance.collection('notifications').add({
          'title': message.notification!.title,
          'body': message.notification!.body,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }

    void setupFirebaseMessaging() {
      FirebaseMessaging.onMessage.listen(_onMessageHandler);
    }

    // Manipula notificações recebidas enquanto o app está em foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Notificação recebida em foreground: ${message.notification?.title}");
    });

    // Manipula notificações recebidas enquanto o app está em background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Notificação aberta a partir do background: ${message.notification?.title}");
    });

    // Inicializa a formatação de data para PT-BR
    await initializeDateFormatting('pt_BR', null);

    // Verifica conectividade e sincroniza dados quando necessário
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        syncData();
      }
    });
  } catch (e) {
    print("Erro ao inicializar o Firebase: $e");
  }
}

/// Função para sincronizar dados locais com o Firestore
Future<void> syncData() async {
  try {
    print("Sincronizando dados com o Firestore...");
    final trucksSnapshot = await FirebaseFirestore.instance.collection('trucks').get();
    for (var doc in trucksSnapshot.docs) {
      print("Sincronizando caminhão: ${doc.id}");
      // Atualize os dados conforme necessário
    }
  } catch (e) {
    print("Erro ao sincronizar dados: $e");
  }
}

class MaintenanceApp extends StatelessWidget {
  const MaintenanceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manutenção de Caminhões',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: TruckListPage(),
    );
  }
}
