import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// 👉 Aquí pegarás la URL de tu webhook de n8n (paso 6 de la guía).
const String n8nWebhookUrl = 'https://guroo.app.n8n.cloud/webhook-test/4e96941b-c76b-4443-87be-b5e15d033154';

// 👉 Datos del vendedor (la panadería). Cámbialos por los que quieras.
const String nombrePanaderia = 'PANADERÍA EL TRIGAL';
const String nifPanaderia = 'B12345678';
const String direccionPanaderia = 'Calle Mayor 1, Talavera de la Reina';

void main() => runApp(const PanaderiaApp());

class PanaderiaApp extends StatelessWidget {
  const PanaderiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panadería',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      home: const PantallaVenta(),
    );
  }
}

// Un producto de la panadería. Los precios son SIN IVA.
class Producto {
  final String nombre;
  final double precio;
  final double iva; // 0.04 = 4 %
  const Producto(this.nombre, this.precio, this.iva);
}

// Puedes cambiar, añadir o quitar productos aquí.
const List<Producto> productos = [
  Producto('Barra de pan', 1.00, 0.04),
  Producto('Pan integral', 1.80, 0.04),
  Producto('Croissant', 1.50, 0.10),
  Producto('Napolitana de chocolate', 1.70, 0.10),
  Producto('Palmera', 1.60, 0.10),
  Producto('Tarta de queso (ración)', 3.50, 0.10),
];

class PantallaVenta extends StatefulWidget {
  const PantallaVenta({super.key});

  @override
  State<PantallaVenta> createState() => _PantallaVentaState();
}

class _PantallaVentaState extends State<PantallaVenta> {
  final Map<Producto, int> _carrito = {};
  final TextEditingController _cliente = TextEditingController();
  final TextEditingController _nif = TextEditingController();
  int _numeroFactura = 1;
  bool _pideDatos = false; // true = factura completa con datos del cliente

  double get _base =>
      _carrito.entries.fold(0, (s, e) => s + e.key.precio * e.value);

  double get _iva =>
      _carrito.entries.fold(0, (s, e) => s + e.key.precio * e.key.iva * e.value);

  double get _total => _base + _iva;

  void _sumar(Producto p) =>
      setState(() => _carrito[p] = (_carrito[p] ?? 0) + 1);

  void _restar(Producto p) {
    setState(() {
      final actual = _carrito[p] ?? 0;
      if (actual <= 1) {
        _carrito.remove(p);
      } else {
        _carrito[p] = actual - 1;
      }
    });
  }

  Future<String> _enviarAn8n(Map<String, dynamic> factura) async {
    if (n8nWebhookUrl.startsWith('PEGA')) {
      return 'n8n sin configurar (la factura solo se ha creado en la app).';
    }
    try {
      final r = await http.post(
        Uri.parse(n8nWebhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(factura),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return 'Enviada a n8n correctamente ✅';
      }
      return 'n8n respondió con error ${r.statusCode}';
    } catch (e) {
      return 'No se pudo conectar con n8n: $e';
    }
  }

  Future<void> _emitirFactura() async {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Añade al menos un producto')),
      );
      return;
    }

    final ahora = DateTime.now();
    final numero = 'F-${ahora.year}-${_numeroFactura.toString().padLeft(4, '0')}';
    final fecha =
        '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

    final lineas = _carrito.entries
        .map((e) => {
              'producto': e.key.nombre,
              'cantidad': e.value,
              'precio_unitario': e.key.precio,
              'iva_porcentaje': (e.key.iva * 100).round(),
              'subtotal': double.parse((e.key.precio * e.value).toStringAsFixed(2)),
            })
        .toList();

    final Map<String, dynamic> factura = {
      'numero': numero,
      'fecha': fecha,
      'tipo': _pideDatos ? 'completa' : 'simplificada',
      'emisor': {
        'nombre': nombrePanaderia,
        'nif': nifPanaderia,
        'direccion': direccionPanaderia,
      },
      'cliente': (_pideDatos && _cliente.text.isNotEmpty) ? _cliente.text : null,
      'nif_cliente': (_pideDatos && _nif.text.isNotEmpty) ? _nif.text : null,
      'lineas': lineas,
      'base_imponible': double.parse(_base.toStringAsFixed(2)),
      'iva': double.parse(_iva.toStringAsFixed(2)),
      'total': double.parse(_total.toStringAsFixed(2)),
    };

    final estado = await _enviarAn8n(factura);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Factura $numero'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(nombrePanaderia,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('NIF: $nifPanaderia'),
              const Text(direccionPanaderia),
              Text('Factura ${_pideDatos ? 'completa' : 'simplificada'}'),
              Text('Fecha: $fecha'),
              if (_pideDatos && _cliente.text.isNotEmpty)
                Text('Cliente: ${_cliente.text}'),
              if (_pideDatos && _nif.text.isNotEmpty)
                Text('NIF cliente: ${_nif.text}'),
              const Divider(),
              for (final e in _carrito.entries)
                Text(
                    '${e.value} x ${e.key.nombre}  ${(e.key.precio * e.value).toStringAsFixed(2)} €'),
              const Divider(),
              Text('Base: ${_base.toStringAsFixed(2)} €'),
              Text('IVA: ${_iva.toStringAsFixed(2)} €'),
              Text('TOTAL: ${_total.toStringAsFixed(2)} €',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(estado, style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    setState(() {
      _carrito.clear();
      _cliente.clear();
      _nif.clear();
      _pideDatos = false;
      _numeroFactura++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🥖 Panadería El Trigal')),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('El cliente pide factura con sus datos'),
            value: _pideDatos,
            onChanged: (v) => setState(() => _pideDatos = v),
          ),
          if (_pideDatos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _cliente,
                      decoration: const InputDecoration(
                          labelText: 'Nombre / empresa',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _nif,
                      decoration: const InputDecoration(
                          labelText: 'NIF del cliente',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: productos.length,
              itemBuilder: (context, i) {
                final p = productos[i];
                final cantidad = _carrito[p] ?? 0;
                return ListTile(
                  title: Text(p.nombre),
                  subtitle: Text(
                      '${p.precio.toStringAsFixed(2)} € + ${(p.iva * 100).round()}% IVA'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: cantidad > 0 ? () => _restar(p) : null,
                      ),
                      Text('$cantidad', style: const TextStyle(fontSize: 18)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _sumar(p),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: Text('Total: ${_total.toStringAsFixed(2)} €',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: _emitirFactura,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Emitir factura'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}