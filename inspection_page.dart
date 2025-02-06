import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import do Firestore
import 'package:http/http.dart' as http; // Para enviar requisições HTTP
import 'dart:convert'; // Para codificar/decodificar JSON
import 'maintenance_schedule.dart';
import 'inspection_history_page.dart';
import 'package:googleapis_auth/auth_io.dart' as auth; // Para autenticação OAuth 2.0
import 'package:flutter/services.dart' show rootBundle; // Para usar rootBundle

class TruckInspectionPage extends StatefulWidget {
  final String truckId;
  final int initialMileage;

  const TruckInspectionPage({
    required this.truckId,
    required this.initialMileage,
    Key? key,
  }) : super(key: key);

  @override
  _TruckInspectionPageState createState() => _TruckInspectionPageState();
}

class _TruckInspectionPageState extends State<TruckInspectionPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância do Firestore
  int? lastRecordedMileage;
  int? currentMileage;
  String? truckName; // Variável para armazenar o nome da carreta


  // Criando um mapa para armazenar a quilometragem de manutenção de cada item
  final Map<String, int?> lastRecordedMaintenance = {
    'oilChange': null,
    'airFilter': null,
    'tires': null,
    'radiatorFluid': null,
  };

  final Map<String, int> recommendedMileage = {
    'oilChange': 20000,
    'airFilter': 10000,
    'tires': 30000,
    'radiatorFluid': 15000,
  };

  @override
  void initState() {
    super.initState();
    _loadMileageData();
  }

  Future<void> _loadMileageData() async {
    final truckSnapshot = await _firestore.collection('trucks').doc(widget.truckId).get();

    if (truckSnapshot.exists) {
      final data = truckSnapshot.data() as Map<String, dynamic>;
      setState(() {
        currentMileage = data['currentMileage'] ?? widget.initialMileage;
        lastRecordedMileage = data['lastRecordedMileage'] ?? 0;
        truckName = data['name']; // Armazena o nome da carreta

        // Carregar as quilometragens de manutenção
        lastRecordedMaintenance['oilChange'] = data['lastMaintenance_oilChange'];
        lastRecordedMaintenance['airFilter'] = data['lastMaintenance_airFilter'];
        lastRecordedMaintenance['tires'] = data['lastMaintenance_tires'];
        lastRecordedMaintenance['radiatorFluid'] = data['lastMaintenance_radiatorFluid'];
      });
    } else {
      setState(() {
        currentMileage = widget.initialMileage;
        lastRecordedMileage = 0;
      });
    }
  }

  Future<void> _saveMileageData() async {
    final truckRef = _firestore.collection('trucks').doc(widget.truckId);

    // Cria um mapa com os dados a serem atualizados
    final Map<String, dynamic> updateData = {
      'currentMileage': currentMileage,
      'lastRecordedMileage': lastRecordedMileage,
    };

    // Adiciona apenas os campos preenchidos ao mapa
    lastRecordedMaintenance.forEach((key, value) {
      if (value != null) {
        updateData['lastMaintenance_$key'] = value;
      }
    });

    // Atualiza o documento no Firestore
    await truckRef.set(updateData, SetOptions(merge: true));
  }

  String _getMaintenanceStatus(String maintenanceType) {
    if (currentMileage == null || lastRecordedMaintenance[maintenanceType] == null) {
      return 'Preencha a quilometragem';
    }

    final mileageSinceLastMaintenance = currentMileage! - (lastRecordedMaintenance[maintenanceType] ?? currentMileage!);
    final remainingKm = recommendedMileage[maintenanceType]! - mileageSinceLastMaintenance;

    if (remainingKm <= 0) {
      return 'Vencido';
    } else if (remainingKm <= 2000) {
      return 'Programar';
    } else {
      return 'Aprovado';
    }
  }

  Future _sendNotification(String truckId, String maintenanceType, String status) async {
  // Endpoint da API FCM HTTP v1
  const String fcmEndpoint = 'https://fcm.googleapis.com/v1/projects/manutencao-push/messages:send';

  // Constrói o corpo da mensagem (payload)
  final Map<String, dynamic> message = {
    'message': {
      'topic': 'manutencao',
      'notification': {
        'title': 'Alerta de Manutenção',
        'body': status == 'Vencido'
            ? 'A Carreta $truckName precisa de manutenção URGENTE para o serviço de $maintenanceType!'
            : 'A Carreta $truckName precisa PROGRAMAR manutenção para o serviço de $maintenanceType.',
      },
      'apns': {
        'payload': {
          'aps': {
            'sound': 'default', // Adiciona som à notificação no iOS
          },
        },
      },  
    },
  };

  // Carrega as credenciais da conta de serviço
  final accountCredentials = auth.ServiceAccountCredentials.fromJson(
    jsonDecode(await rootBundle.loadString('assets/service_account_key.json')),
  );

  // Cria um cliente HTTP autenticado
  final client = await auth.clientViaServiceAccount(accountCredentials, ['https://www.googleapis.com/auth/firebase.messaging']);

  try {
    // Envia a solicitação HTTP POST
    final response = await client.post(
      Uri.parse(fcmEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(message),
    );

    // Verifica a resposta
    if (response.statusCode == 200) {
      print('Notificação enviada com sucesso!');
    } else {
      print('Erro ao enviar notificação: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    print('Erro ao enviar notificação: $e');
  } finally {
    client.close(); // Fecha o cliente HTTP
  }
}

  void _submitInspection() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() {
        lastRecordedMileage = currentMileage;
      });

      _saveMileageData();

      // Verifica o status de cada item de manutenção
      recommendedMileage.keys.forEach((type) {
        final status = _getMaintenanceStatus(type);
        if (status == 'Vencido' || status == 'Programar') {
          _sendNotification(widget.truckId, _getItemName(type), status);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspeção salva com sucesso!')),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inspeção - ${truckName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Última quilometragem registrada
              TextFormField(
                initialValue: lastRecordedMileage != null
                    ? lastRecordedMileage.toString()
                    : 'Carregando...',
                decoration: const InputDecoration(labelText: 'Última Quilometragem Registrada'),
                enabled: false,
                key: ValueKey(lastRecordedMileage),
              ),
              const SizedBox(height: 20),

              // Quilometragem Atual
              TextFormField(
                initialValue: currentMileage?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Quilometragem Atual'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira a quilometragem atual';
                  }
                  final int? parsedValue = int.tryParse(value);
                  if (parsedValue == null || parsedValue < (lastRecordedMileage ?? 0)) {
                    return 'A quilometragem deve ser maior ou igual à última registrada';
                  }
                  return null;
                },
                onSaved: (value) {
                  currentMileage = int.tryParse(value!);
                },
                onChanged: (value) {
                  setState(() {
                    currentMileage = int.tryParse(value);
                  });
                },
              ),
              const SizedBox(height: 20),

              // Itens e status de manutenção
              const Text(
                'Itens a serem inspecionados e seu status de manutenção:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),

              DataTable(
                columns: const [
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Última Manutenção')),
                ],
                rows: recommendedMileage.keys.map((type) {
                  final status = _getMaintenanceStatus(type);
                  return DataRow(cells: [
                    DataCell(Text(_getItemName(type))),
                    DataCell(_getStatusIcon(status)),
                    DataCell(Text(lastRecordedMaintenance[type]?.toString() ?? 'Não registrada')),
                  ]);
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Seção de Botões Organizados
              const SizedBox(height: 20), // Espaçamento acima dos botões
              Wrap(
                spacing: 10, // Espaço horizontal entre os botões
                runSpacing: 10, // Espaço vertical quando os botões quebram para nova linha
                alignment: WrapAlignment.center, // Centraliza os botões
                children: [
                  ElevatedButton(
                    onPressed: _submitInspection,
                    child: const Text('Salvar Inspeção'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MaintenanceSchedulePage(
                            truckId: widget.truckId,
                            lastRecordedMileage: lastRecordedMileage ?? 0,
                          ),
                        ),
                      );

                      if (result == true) {
                        _loadMileageData(); // Recarrega os dados atualizados
                      }
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Registrar Revisão'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InspectionHistoryPage(truckId: widget.truckId),
                        ),
                      );
                    },
                    child: const Text('Ver Histórico'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getItemName(String key) {
    switch (key) {
      case 'oilChange':
        return 'Troca de Óleo';
      case 'airFilter':
        return 'Filtro de Ar';
      case 'tires':
        return 'Pneus';
      case 'radiatorFluid':
        return 'Fluido do Radiador';
      default:
        return key;
    }
  }

  Icon _getStatusIcon(String status) {
    switch (status) {
      case 'Vencido':
        return const Icon(Icons.warning, color: Colors.red);
      case 'Programar':
        return const Icon(Icons.schedule, color: Colors.orange);
      case 'Aprovado':
        return const Icon(Icons.check_circle, color: Colors.green);
      default:
        return const Icon(Icons.help, color: Colors.grey);
    }
  }
}
