import 'package:flutter/material.dart';
import 'inspection_page.dart';
import 'driver_registration_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TruckListPage extends StatefulWidget {
  @override
  _TruckListPageState createState() => _TruckListPageState();
}

class _TruckListPageState extends State<TruckListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _newTruckController = TextEditingController();
  bool _isAddingTruck = false;

  // Método para calcular o status da manutenção
  String _calculateMaintenanceStatus(Map<String, dynamic> truckData) {
    final currentMileage = truckData['currentMileage'] ?? 0;
    final lastMaintenanceOilChange = truckData['lastMaintenance_oilChange'] ?? 0;
    final lastMaintenanceAirFilter = truckData['lastMaintenance_airFilter'] ?? 0;
    final lastMaintenanceTires = truckData['lastMaintenance_tires'] ?? 0;
    final lastMaintenanceRadiatorFluid = truckData['lastMaintenance_radiatorFluid'] ?? 0;

    // Quilometragens recomendadas
    const recommendedOilChange = 20000;
    const recommendedAirFilter = 10000;
    const recommendedTires = 30000;
    const recommendedRadiatorFluid = 15000;

    // Verifica o status de cada item de manutenção
    final statuses = [
      _getItemStatus(currentMileage, lastMaintenanceOilChange, recommendedOilChange),
      _getItemStatus(currentMileage, lastMaintenanceAirFilter, recommendedAirFilter),
      _getItemStatus(currentMileage, lastMaintenanceTires, recommendedTires),
      _getItemStatus(currentMileage, lastMaintenanceRadiatorFluid, recommendedRadiatorFluid),
    ];

    // Define o status geral da carreta
    if (statuses.contains('Vencido')) {
      return 'Vencido';
    } else if (statuses.contains('Programar')) {
      return 'Programar';
    } else {
      return 'Aprovado';
    }
  }

  // Método para calcular o status de um item de manutenção
  String _getItemStatus(int currentMileage, int lastMaintenance, int recommendedMileage) {
    final mileageSinceLast = currentMileage - lastMaintenance;
    if (mileageSinceLast >= recommendedMileage) {
      return 'Vencido';
    } else if (recommendedMileage - mileageSinceLast <= 2000) {
      return 'Programar';
    } else {
      return 'Aprovado';
    }
  }

  Stream<List<Map<String, dynamic>>> _truckStream() {
    return _firestore.collection('trucks').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final truckData = doc.data();
        return {
          'id': doc.id,
          'name': truckData['name'],
          'status': _calculateMaintenanceStatus(truckData), // Calcula o status dinamicamente
        };
      }).toList();
    });
  }

  Future<void> _addTruck() async {
    String newTruck = _newTruckController.text.trim();
    if (newTruck.isNotEmpty) {
      var existingTruck = await _firestore
          .collection('trucks')
          .where('name', isEqualTo: newTruck)
          .get();

      if (existingTruck.docs.isNotEmpty) {
        _showSnackBar('Já existe uma carreta com esse nome!');
        return;
      }

      await _firestore.collection('trucks').add({
        'name': newTruck,
        'currentMileage': 0,
        'lastMaintenance_oilChange': 0,
        'lastMaintenance_airFilter': 0,
        'lastMaintenance_tires': 0,
        'lastMaintenance_radiatorFluid': 0,
        'status': 'Aprovado', // Status inicial
      });

      _showSnackBar('Carreta adicionada com sucesso!');
      _newTruckController.clear();
      setState(() {
        _isAddingTruck = false;
      });
    }
  }

  Future<void> _removeTruck(String truckId) async {
    bool confirmDelete = await _confirmDelete();
    if (confirmDelete) {
      await _firestore.collection('trucks').doc(truckId).delete();
      _showSnackBar('Carreta removida com sucesso!');
    }
  }

  Future<bool> _confirmDelete() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar exclusão'),
            content: const Text('Deseja realmente remover esta carreta?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showAddTruckDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar Nova Carreta'),
        content: TextField(
          controller: _newTruckController,
          decoration: const InputDecoration(labelText: 'Nome da carreta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _addTruck();
              Navigator.of(context).pop();
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _navigateToManageTrucks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _truckStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Gerenciar Carretas')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final trucks = snapshot.data!;
            return ManageTrucksPage(
              trucks: trucks,
              removeTruck: _removeTruck,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manutenção da Frota')),
      drawer: _buildDrawer(),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _truckStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final trucks = snapshot.data!;
          return Column(
            children: [
              if (trucks.any((t) => t['status'] == 'Vencido' || t['status'] == 'Programar'))
                _buildWarningBanner(),
              Expanded(
                child: ListView.builder(
                  itemCount: trucks.length,
                  itemBuilder: (context, index) {
                    final truck = trucks[index];
                    return ListTile(
                      title: Text(truck['name']),
                      subtitle: Row(
                        children: [
                          Text('Status: ${truck['status']}'),
                          const SizedBox(width: 8),
                          if (truck['status'] == 'Vencido')
                            const Icon(Icons.warning, color: Colors.red),
                          if (truck['status'] == 'Programar')
                            const Icon(Icons.schedule, color: Colors.orange),
                          if (truck['status'] == 'Aprovado')
                            const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TruckInspectionPage(
                              truckId: truck['id'],
                              initialMileage: 0,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.orangeAccent,
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Atenção! Existem manutenções pendentes ou vencidas.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 150,
            color: Colors.white,
            child: Center(
              child: Image.asset(
                'assets/logo_cliente.png',
                fit: BoxFit.contain,
                width: 120,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Adicionar Carreta'),
            onTap: () {
              Navigator.pop(context);
              _showAddTruckDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Cadastrar Motorista'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => DriverRegistrationPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Gerenciar Carretas'),
            onTap: () {
              Navigator.pop(context); // Fecha o Drawer
              _navigateToManageTrucks();
            },
          ),
        ],
      ),
    );
  }
}

// Tela de Gerenciamento de Carretas
class ManageTrucksPage extends StatelessWidget {
  final List<Map<String, dynamic>> trucks;
  final Function(String) removeTruck;

  const ManageTrucksPage({
    required this.trucks,
    required this.removeTruck,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Carretas')),
      body: trucks.isEmpty
          ? const Center(child: Text('Nenhuma carreta cadastrada.'))
          : ListView.builder(
              itemCount: trucks.length,
              itemBuilder: (context, index) {
                final truck = trucks[index];
                return ListTile(
                  title: Text(truck['name']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => removeTruck(truck['id']),
                  ),
                );
              },
            ),
    );
  }
}
