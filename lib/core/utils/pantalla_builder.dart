import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/placeholder_screen.dart';
import '../../features/categorias/presentation/screens/categorias_screen.dart';
import '../../features/productos/presentation/screens/inventario_screen.dart';
import '../../features/usuarios/presentation/screens/usuarios_screen.dart';
import '../../features/negocio/presentation/screens/negocio_screen.dart';
import '../../features/colores/presentation/screens/colores_screen.dart';
import '../../features/clientes/presentation/screens/clientes_screen.dart';
import '../../features/proveedores/presentation/screens/proveedores_screen.dart';
import '../../features/ventas_credito/presentation/screens/ventas_credito_screen.dart';
import '../../features/compras_credito/presentation/screens/compras_credito_screen.dart';
import '../../features/reportes/presentation/screens/reporte_ventas_screen.dart';
import '../../features/reportes/presentation/screens/reporte_compras_screen.dart';
import '../../features/reportes/presentation/screens/reporte_financiero_screen.dart';
import '../../features/ventas/presentation/screens/registrar_venta_screen.dart';
import '../../features/ventas/presentation/screens/detalle_venta_screen.dart';
import '../../features/ventas/providers/carrito_provider.dart';
import '../../features/compras/presentation/screens/registrar_compra_screen.dart';
import '../../features/compras/presentation/screens/detalle_compra_screen.dart';
import '../../features/compras/presentation/screens/hacer_pedido_screen.dart';
import '../../features/compras/providers/carrito_compra_provider.dart';
import '../../features/caja/presentation/screens/cierre_caja_screen.dart';
import '../../features/egresos/presentation/screens/ingresos_egresos_screen.dart';

Widget construirPantalla(String moduleKey, String titulo, IconData icono) {
  switch (moduleKey) {
    case 'ventas_registrar':
      // Cada pestaña de "Registrar Venta" necesita su propio carrito
      // independiente (el usuario puede tener varias ventas abiertas a la
      // vez); se logra dándole a esta subárbol su propia instancia del
      // provider en vez de compartir la global.
      return ProviderScope(
        overrides: [carritoVentaProvider.overrideWith(() => CarritoVentaNotifier())],
        child: const RegistrarVentaScreen(),
      );
    case 'ventas_detalle':
      return const DetalleVentaScreen(esDialogo: false);
    case 'compras_registrar':
      // Mismo aislamiento por pestaña que 'ventas_registrar': cada pestaña
      // de "Registrar Compra" tiene su propio carrito independiente.
      return ProviderScope(
        overrides: [carritoCompraProvider.overrideWith(() => CarritoCompraNotifier())],
        child: const RegistrarCompraScreen(),
      );
    case 'compras_detalle':
      return const DetalleCompraScreen(esDialogo: false);
    case 'compras_pedido':
      return const HacerPedidoScreen();
    case 'categorias':
      return const CategoriasScreen();
    case 'inventario':
      return const InventarioScreen();
      case 'usuarios':
      return const UsuariosScreen();
    case 'negocio':
      return const NegocioScreen();
    case 'colores':
      return const ColoresScreen();
    case 'clientes':
      return const ClientesScreen();
    case 'proveedores':
      return const ProveedoresScreen();
    case 'ventas_credito':
      return const VentasCreditoScreen();
    case 'compras_credito':
      return const ComprasCreditoScreen();
    case 'reporte_ventas':
      return const ReporteVentasScreen();
    case 'reporte_compras':
      return const ReporteComprasScreen();
    case 'reporte_financiero':
      return const ReporteFinancieroScreen();
    case 'cierre_caja':
      return const CierreCajaScreen();
    case 'ingresos_egresos':
      return const IngresosEgresosScreen();
    default:
      return PlaceholderScreen(titulo: titulo, icono: icono);
  }
}